*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${ADMIN_USER}        admin
${ADMIN_PASSWORD}    Nethesis,1234
# The schema demands a dot, nothing resolves it: curl uses --resolve
${TEST_HOST}         lemp.ns8-ci.test
${DB_PASSWORD}       Ns8,Lemp-Db1
${DB_PASSWORD2}      Ns8,Lemp-Db2
${MARIADB_ADMIN}     Ns8,Lemp-Admin1
${MARIADB_ADMIN2}    Ns8,Lemp-Admin2
${BASE_CONFIG}       "host":"${TEST_HOST}","lets_encrypt":false,"document_root":"","nginx_preset":"generic","php_memory_limit":"256M","php_upload_max_filesize":"64M","php_max_execution_time":300,"php_timezone":"Europe/Paris","fpm_pm_max_children":5,"phpmyadmin_enabled":true,"db_name":"app","db_user":"app","user_domain":"","mail_from":""

*** Keywords ***
An invalid custom file is refused
    [Arguments]    ${path}    ${content}
    In the module    sh -c 'cp ${path} /tmp/custom.bak && printf "${content}\\n" > ${path}'
    Configure    "php_version":"8.4","php_memory_limit":"300M"    rc_expected=1
    The site answers
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config['php_memory_limit']}    256M
    In the module    mv /tmp/custom.bak ${path}

Login to cluster-admin
    New Page    https://${NODE_ADDR}/cluster-admin/
    Fill Text    text="Username"    ${ADMIN_USER}
    Click    button >> text="Continue"
    Fill Text    text="Password"    ${ADMIN_PASSWORD}
    Click    button >> text="Log in"
    Wait For Elements State    css=#main-content    visible    timeout=10s

Configure
    [Arguments]    ${extra}    ${rc_expected}=0
    ${output} =    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},${extra}}
    ...    decode_json=${FALSE}    rc_expected=${rc_expected}
    IF    ${rc_expected} == 0    The configuration is    {${BASE_CONFIG},${extra}}
    RETURN    ${output}

The configuration is
    [Documentation]    get-configuration returns every value sent, passwords aside
    [Arguments]    ${payload}
    ${sent} =    Evaluate    {k: v for k, v in json.loads($payload).items() if not k.endswith("_password")}    modules=json
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    FOR    ${key}    IN    @{sent}
        Should Be Equal    ${config['${key}']}    ${sent['${key}']}    get-configuration ${key}
    END

Fetch
    [Arguments]    ${path}
    ${page} =    Execute Command    curl -sk --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}${path}
    RETURN    ${page}

HTTP code
    [Arguments]    ${path}
    ${code} =    Execute Command    curl -sk -o /dev/null -w "\%{http_code}" --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}${path}
    RETURN    ${code}

The site answers
    ${code} =    HTTP code    /
    Should Be Equal    ${code}    200

In the module
    [Arguments]    ${command}
    ${output}    ${rc} =    Execute Command    runagent -m ${module_id} ${command}    return_rc=True
    Should Be Equal As Integers    ${rc}    0    ${output}
    RETURN    ${output}

SQL as
    [Arguments]    ${user}    ${password}    ${sql}
    ${output}    ${rc} =    Execute Command
    ...    printf '%s' '${sql}' | runagent -m ${module_id} podman exec -i -e MYSQL_PWD='${password}' mariadb-app mariadb -u${user} -h127.0.0.1 -N    return_rc=True
    RETURN    ${output}    ${rc}

Check PHP version
    [Arguments]    ${version}
    Configure    "php_version":"${version}"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    PHP Version ${version}.
    Should Contain    ${page}    <tr><td class="e">memory_limit</td><td class="v">256M</td>
    Should Contain    ${page}    <tr><td class="e">upload_max_filesize</td><td class="v">64M</td>
    Should Contain    ${page}    <tr><td class="e">max_execution_time</td><td class="v">300</td>
    Should Contain    ${page}    <tr><td class="e">date.timezone</td><td class="v">Europe/Paris</td>

*** Test Cases ***
Check if lemp is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check the fresh configuration
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Not Be True    ${config['db_password_set']}
    Should Not Be True    ${config['admin_password_set']}
    Should Be True    ${config['phpmyadmin_enabled']}
    Should Match Regexp    ${config['phpmyadmin_path']}    ^phpmyadmin-[0-9a-f]{8}$
    Set Suite Variable    ${PMA_PATH}    /${config['phpmyadmin_path']}/

Check missing passwords are rejected
    ${output} =    Configure    "php_version":"8.4"    rc_expected=2
    Should Contain    ${output}    db_password_required
    Should Contain    ${output}    admin_password_required

Check a weak password is rejected
    ${output} =    Configure    "php_version":"8.4","db_password":"abcdefgh","admin_password":"${MARIADB_ADMIN}"    rc_expected=2
    Should Contain    ${output}    db_password_too_weak

Check if lemp can be configured
    Configure    "php_version":"8.4","db_password":"${DB_PASSWORD}","admin_password":"${MARIADB_ADMIN}"
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be True    ${config['db_password_set']}
    Should Be True    ${config['admin_password_set']}
    Should Be Equal    ${config['versions']['mariadb']}    12.3.3
    Should Start With    ${config['versions']['php']}    8.4.

Check the site answers over HTTPS
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /
    Should Contain    ${page}    NS8 LEMP is running
    Should Contain    ${page}    MariaDB</td><td>12.3.3

Check the phpinfo page hides the passwords
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    memory_limit
    Should Not Contain    ${page}    ${DB_PASSWORD}
    Should Not Contain    ${page}    LEMP_DB_PASSWORD

Check the site can call itself
    ${code} =    In the module    podman exec php-fpm-app curl -sk -o /dev/null -w "\%{http_code}" https://${TEST_HOST}/
    Should Be Equal    ${code}    200

Check the database accounts
    ${output}    ${rc} =    SQL as    app    ${DB_PASSWORD}    SELECT DATABASE() FROM DUAL; SHOW DATABASES;
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${output}    app
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN}    SHOW GRANTS;
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${output}    GRANT ALL PRIVILEGES ON *.* TO `admin`@`%`
    Should Contain    ${output}    WITH GRANT OPTION
    # root is reachable only from inside the MariaDB container
    ${output}    ${rc} =    SQL as    root    ${EMPTY}    SELECT 1;
    Should Not Be Equal As Integers    ${rc}    0

Check the database password can change
    Configure    "php_version":"8.4","db_password":"${DB_PASSWORD2}"
    ${output}    ${rc} =    SQL as    app    ${DB_PASSWORD2}    SELECT 1;
    Should Be Equal As Integers    ${rc}    0
    ${output}    ${rc} =    SQL as    app    ${DB_PASSWORD}    SELECT 1;
    Should Not Be Equal As Integers    ${rc}    0

Check the database name cannot change
    ${output} =    Run task    module/${module_id}/configure-module    {${BASE_CONFIG.replace('"db_name":"app"', '"db_name":"other"')},"php_version":"8.4"}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    db_name_cannot_change

Check phpMyAdmin is served on its random path only
    ${page} =    Fetch    ${PMA_PATH}
    Should Contain    ${page}    name="pma_username"
    ${page} =    Fetch    /phpmyadmin/
    Should Not Contain    ${page}    pma_username

Check phpMyAdmin can be disabled
    Configure    "php_version":"8.4","phpmyadmin_enabled":false
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    ${PMA_PATH}
    Should Not Contain    ${page}    pma_username
    Configure    "php_version":"8.4"

Check the WordPress preset
    In the module    podman exec php-fpm-app sh -c 'printf "<?php echo \\"route=\\".\\$_SERVER[\\"REQUEST_URI\\"];" > /app/router.php'
    Configure    "php_version":"8.4","nginx_preset":"wordpress"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${code} =    HTTP code    /xmlrpc.php
    Should Be Equal    ${code}    403
    ${code} =    HTTP code    /wp-content/uploads/evil.php
    Should Be Equal    ${code}    403
    ${code} =    HTTP code    /.htaccess
    Should Be Equal    ${code}    403

Check a permalink reaches index.php
    ${page} =    Fetch    /a-permalink/
    Should Contain    ${page}    NS8 LEMP is running
    Configure    "php_version":"8.4"

Check an invalid custom file is refused without outage
    In the module    sh -c 'cp nginx/custom.d/90-custom.conf nginx/custom.d/90-custom.conf.bak && echo "bogus_directive on;" >> nginx/custom.d/90-custom.conf'
    ${output} =    Configure    "php_version":"8.4","php_memory_limit":"300M"    rc_expected=1
    The site answers
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    <tr><td class="e">memory_limit</td><td class="v">256M</td>
    In the module    mv nginx/custom.d/90-custom.conf.bak nginx/custom.d/90-custom.conf

Check each invalid custom file is refused
    [Template]    An invalid custom file is refused
    php/fpm.d/90-custom.conf    [www]\\npm.bogus = 1
    mariadb/90-custom.cnf    [mysqld]\\nbogus_option = 1
    php/php.d/90-custom.ini    foo[ = 1

Check the nginx, PHP-FPM and MariaDB custom files are applied
    In the module    sh -c 'cp nginx/custom.d/90-custom.conf /tmp/n.bak && echo "add_header X-Lemp-Test custom;" > nginx/custom.d/90-custom.conf'
    In the module    sh -c 'cp php/fpm.d/90-custom.conf /tmp/f.bak && printf "[www]\\npm.max_requests = 321\\n" > php/fpm.d/90-custom.conf'
    In the module    sh -c 'cp mariadb/90-custom.cnf /tmp/m.bak && printf "[mysqld]\\nmax_connections = 77\\n" > mariadb/90-custom.cnf'
    Configure    "php_version":"8.4"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${headers} =    Execute Command    curl -sk -D - -o /dev/null --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/
    Should Contain    ${headers}    x-lemp-test: custom
    ${fpm} =    In the module    podman exec php-fpm-app sh -c 'php-fpm -tt 2>&1'
    Should Match Regexp    ${fpm}    pm.max_requests = 321\\b
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN}    SELECT @@max_connections;
    Should Be Equal    ${output}    77
    In the module    sh -c 'mv /tmp/n.bak nginx/custom.d/90-custom.conf && mv /tmp/f.bak php/fpm.d/90-custom.conf && mv /tmp/m.bak mariadb/90-custom.cnf'
    Configure    "php_version":"8.4"

Check a custom file is kept and applied
    In the module    sh -c 'echo "max_input_vars = 4321" > php/php.d/90-custom.ini'
    Configure    "php_version":"8.4"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    <tr><td class="e">max_input_vars</td><td class="v">4321</td>
    ${custom} =    In the module    cat php/php.d/90-custom.ini
    Should Contain    ${custom}    max_input_vars = 4321

Check the cron jobs run
    # A script file keeps the crontab line free of nested quotes
    In the module    podman exec php-fpm-app sh -c 'echo "<?php file_put_contents(\\"/app/cron.txt\\", getenv(\\"LEMP_DB_NAME\\"));" > /app/cronjob.php'
    In the module    sh -c 'echo "* * * * * www-data php /app/cronjob.php" >> crontab'
    In the module    systemctl --user restart cron-app.service
    Wait Until Keyword Succeeds    150 seconds    10 seconds    In the module    podman exec php-fpm-app test -f /app/cron.txt
    ${output} =    In the module    podman exec php-fpm-app cat /app/cron.txt
    Should Be Equal    ${output}    app

Check the backup dump
    In the module    module-dump-state
    ${output} =    In the module    sh -c 'grep -c "CREATE DATABASE.*\\`app\\`" lemp.sql'
    Should Be Equal    ${output}    1
    In the module    module-cleanup-state

Check the PHP settings change
    Configure    "php_version":"8.4","php_memory_limit":"384M","php_upload_max_filesize":"32M","php_max_execution_time":120,"php_timezone":"UTC"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    <tr><td class="e">memory_limit</td><td class="v">384M</td>
    Should Contain    ${page}    <tr><td class="e">upload_max_filesize</td><td class="v">32M</td>
    Should Contain    ${page}    <tr><td class="e">post_max_size</td><td class="v">32M</td>
    Should Contain    ${page}    <tr><td class="e">max_execution_time</td><td class="v">120</td>
    Should Contain    ${page}    <tr><td class="e">date.timezone</td><td class="v">UTC</td>
    # nginx takes the same upload limit and timeout
    ${nginx} =    In the module    podman exec nginx-app nginx -T
    Should Contain    ${nginx}    client_max_body_size 32M;
    Should Contain    ${nginx}    fastcgi_read_timeout 120s;

Check the PHP-FPM workers change
    Configure    "php_version":"8.4","fpm_pm_max_children":7
    ${fpm} =    In the module    podman exec php-fpm-app sh -c 'php-fpm -tt 2>&1'
    Should Match Regexp    ${fpm}    pm.max_children = 7\\b

Check the InnoDB buffer pool follows the node memory
    # 5% of the node memory in 64 MiB steps, between 128 MiB and 1 GiB
    ${kib} =    Execute Command    awk '/^MemTotal:/ {print $2}' /proc/meminfo
    ${mib} =    Evaluate    min(max(int(${kib}) // 1024 * 5 // 100 // 64 * 64, 128), 1024)
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN}    SELECT @@innodb_buffer_pool_size;
    Should Be Equal As Integers    ${rc}    0
    Should Be Equal As Integers    ${output}    ${mib * 1024 * 1024}

Check the memory limit must exceed the upload limit
    ${output} =    Configure    "php_version":"8.4","php_memory_limit":"256M","php_upload_max_filesize":"256M"    rc_expected=2
    Should Contain    ${output}    php_memory_limit_too_low

Check the execution time can be unlimited
    Configure    "php_version":"8.4","php_max_execution_time":0
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /phpinfo.php
    Should Contain    ${page}    <tr><td class="e">max_execution_time</td><td class="v">0</td>
    ${nginx} =    In the module    podman exec nginx-app nginx -T
    Should Contain    ${nginx}    fastcgi_read_timeout 86400s;
    ${fpm} =    In the module    podman exec php-fpm-app sh -c 'php-fpm -tt 2>&1'
    Should Match Regexp    ${fpm}    request_terminate_timeout = 0s?\\b
    ${output} =    Configure    "php_version":"8.4","php_max_execution_time":7200    rc_expected=10
    Configure    "php_version":"8.4"

Check an update brings old settings in range
    # Settings an older release could hold: buffer pool in the environment, sizes in K,
    # memory below upload, execution time and workers above the current limits
    In the module    python3 -c 'import agent; [agent.set_env(k, v) for k, v in {"MARIADB_INNODB_BUFFER_POOL_SIZE": "160M", "PHP_MEMORY_LIMIT": "131072K", "PHP_UPLOAD_MAX_FILESIZE": "256M", "PHP_MAX_EXECUTION_TIME": "7200", "FPM_PM_MAX_CHILDREN": "200"}.items()]'
    ${output}  ${rc} =    Execute Command    api-cli run update-module --data '{"module_url":"${IMAGE_URL}","instances":["${module_id}"],"force":true}'    return_rc=True
    Should Be Equal As Integers    ${rc}    0    ${output}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config['php_upload_max_filesize']}    256M
    Should Be Equal    ${config['php_memory_limit']}    512M
    Should Be Equal As Integers    ${config['php_max_execution_time']}    3600
    Should Be Equal As Integers    ${config['fpm_pm_max_children']}    100
    ${env} =    In the module    sh -c 'env | grep -c "^MARIADB_INNODB_BUFFER_POOL_SIZE=" || true'
    Should Be Equal    ${env}    0
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN}    SELECT @@innodb_buffer_pool_size;
    Should Be Equal As Integers    ${output}    167772160
    In the module    sh -c 'grep -q "^innodb_buffer_pool_size = 160M$" mariadb/90-custom.cnf'
    In the module    sed -i '/Moved from the module settings/,/^innodb_buffer_pool_size/d' mariadb/90-custom.cnf
    Configure    "php_version":"8.4"

Check the document root changes
    In the module    podman exec -u www-data php-fpm-app sh -c 'mkdir -p /app/public && echo "<?php echo \\"docroot=public\\";" > /app/public/index.php'
    Configure    "php_version":"8.4","document_root":"public"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /
    Should Be Equal    ${page}    docroot=public
    Configure    "php_version":"8.4"
    ${page} =    Fetch    /
    Should Contain    ${page}    NS8 LEMP is running

Check the document root stays inside the site
    FOR    ${root}    IN    ..    .    ../etc    public/..
        ${output} =    Configure    "php_version":"8.4","document_root":"${root}"    rc_expected=10
        Should Contain    ${output}    document_root
    END

Check the sender address changes
    Configure    "php_version":"8.4","mail_from":"web@example.org"
    ${output} =    In the module    podman exec php-fpm-app printenv MAIL_FROM
    Should Be Equal    ${output}    web@example.org
    ${output} =    In the module    podman exec cron-app grep -c web@example.org /etc/lemp/cron.env
    Should Be Equal    ${output}    1
    Configure    "php_version":"8.4"

Check the admin password can change
    Configure    "php_version":"8.4","admin_password":"${MARIADB_ADMIN2}"
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN2}    SELECT 1;
    Should Be Equal As Integers    ${rc}    0
    ${output}    ${rc} =    SQL as    admin    ${MARIADB_ADMIN}    SELECT 1;
    Should Not Be Equal As Integers    ${rc}    0
    Configure    "php_version":"8.4","admin_password":"${MARIADB_ADMIN}"

Check an unknown user domain is rejected
    ${output} =    Configure    "php_version":"8.4","user_domain":"missing.test"    rc_expected=2
    Should Contain    ${output}    user_domain_not_found

Check the host name changes
    Configure    "php_version":"8.4","host":"lemp2.ns8-ci.test"
    ${code} =    Execute Command    curl -sk -o /dev/null -w "\%{http_code}" --resolve lemp2.ns8-ci.test:443:127.0.0.1 https://lemp2.ns8-ci.test/
    Should Be Equal    ${code}    200
    ${code} =    HTTP code    /
    Should Be Equal    ${code}    404
    ${output} =    In the module    podman exec php-fpm-app printenv NS8_HOSTNAME
    Should Be Equal    ${output}    lemp2.ns8-ci.test
    Configure    "php_version":"8.4"
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers

Check PHP 8.2
    Check PHP version    8.2

Check PHP 8.3
    Check PHP version    8.3

Check PHP 8.5
    Check PHP version    8.5

Check PHP 8.4
    Check PHP version    8.4

Take screenshots
    [Tags]    ui
    Import Library    Browser
    New Browser    chromium    headless=True
    New Context    ignoreHTTPSErrors=True
    Login to cluster-admin
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}
    Wait For Elements State    iframe >>> h2 >> text="Status"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/1._Status.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=settings
    Wait For Elements State    iframe >>> h2 >> text="Settings"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/2._Settings.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=about
    Wait For Elements State    iframe >>> h2 >> text="About"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/3._About.png
    Close Browser

Check if lemp is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

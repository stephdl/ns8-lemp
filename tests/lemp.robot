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
${BASE_CONFIG}       "host":"${TEST_HOST}","lets_encrypt":false,"document_root":"","nginx_preset":"generic","php_memory_limit":"256M","php_upload_max_filesize":"64M","php_max_execution_time":300,"php_timezone":"Europe/Paris","fpm_pm_max_children":5,"mariadb_innodb_buffer_pool_size":"128M","phpmyadmin_enabled":true,"db_name":"app","db_user":"app","user_domain":"","mail_from":""

*** Keywords ***
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
    RETURN    ${output}

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

Check phpMyAdmin is served
    ${page} =    Fetch    /phpmyadmin/
    Should Contain    ${page}    name="pma_username"

Check phpMyAdmin can be disabled
    Configure    "php_version":"8.4","phpmyadmin_enabled":false
    Wait Until Keyword Succeeds    60 seconds    2 seconds    The site answers
    ${page} =    Fetch    /phpmyadmin/
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

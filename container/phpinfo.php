<?php
// PHP-FPM gives the database and LDAP passwords to the site as environment
// variables: the Environment and Variables sections would print them
phpinfo(INFO_GENERAL | INFO_CONFIGURATION | INFO_MODULES);

<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

// Datenbankverbindung (aus Umgebungsvariablen)
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('DB_HOST')  ?: 'moodle_db';
$CFG->dbname    = getenv('DB_NAME')  ?: 'moodledb';
$CFG->dbuser    = getenv('DB_USER')  ?: 'moodleuser';
$CFG->dbpass    = getenv('DB_PASS')  ?: '';
$CFG->prefix    = 'mdl_';

// Pfade und URL
$CFG->wwwroot  = getenv('MOODLE_URL') ?: 'http://localhost';
$CFG->dataroot = '/var/moodledata';
$CFG->directorypermissions = 0777;
$CFG->admin = 'admin';

require_once(__DIR__ . '/lib/setup.php');

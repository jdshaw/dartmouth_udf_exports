This plugin adds some extra fields to ArchivesSpace EAD and MARC
exports based on user defined fields.

Built for Dartmouth college and developed against ArchivesSpace 1.2.x
(although should run against 1.3.x as well)


# Installing it

The usual:

    cd /path/to/your/archivesspace/plugins
    git clone https://github.com/hudmol/dartmouth_udf_exports.git

Then edit `config/config.rb` and add the plugin to the list:

    AppConfig[:plugins] = ['local', 'other_plugins', 'dartmouth_udf_exports']


# Introduction

This plugin will allow a librarian to create a set of overdue notices to print and mail based on a set of criteria the librarian may select.

# Usage

To create your print notices, simply install the plugin, then browse to the report plugins page. Once there select "Run report"
for this plugin. You should be presented with a page of options. From here, you can limit the overdues to be printed by
library, patron category, due date range, notice to print and also specify a single patron if you wish! Submit the form and you will be
presented with a set of notices that you can print from your browser. When printed, each notice will print on a separate page.

**NOTE:** The notice you choose should have a *print* transport version of the notice defined. If there is no *print* transport
version, you will simply get a blank page.

# Downloading

From the [release page](https://github.com/cjlynce/koha-plugin-bill-notices-printer/releases) you can download the relevant *.kpz file

# Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver
* Restart memcached if you are using it

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

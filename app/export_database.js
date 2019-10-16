const { google } = require('googleapis');
const { auth } = require('google-auth-library');
var sqladmin = google.sqladmin("v1beta4");

exports.exportDatabase = (req, res) => {
    async function initiateDatabaseExport() {
        let message = req.query.message || req.body.message || 'Hello World!';
        //console.log('Message received is: ' + JSON.stringify(message));
        let parsedBody;
        if (req.header('content-type') === 'application/json') {
            console.log('request header content-type is application/json and auto parsing the req body as json');
            parsedBody = req.body;
        } else {
            console.log('request header content-type is NOT application/json and MANUALLY parsing the req body as json');
            parsedBody = JSON.parse(req.body);
        }
        console.log('project_name is:' + parsedBody.project_name);
        console.log('mysql_instance_name is:' + parsedBody.mysql_instance_name);
        console.log('bucket_name is:' + parsedBody.bucket_name);

        const authRes = await auth.getApplicationDefault();
        var utc = new Date().toJSON().replace(/-/g, '_').replace(/:/g, '_');
        let authClient = authRes.credential;
        var request = {
            // Project ID of the project that contains the instance to be exported.
            project: parsedBody.project_name,

            // Cloud SQL instance ID. This does not include the project ID.
            instance: parsedBody.mysql_instance_name,
            resource: {
                // Contains details about the export operation.
                exportContext: {
                    // This is always sql#exportContext.
                    kind: "sql#exportContext",
                    // The file type for the specified uri (e.g. SQL or CSV)
                    fileType: "SQL", // CSV
                    /** 
                     * The path to the file in GCS where the export will be stored.
                     * The URI is in the form gs://bucketName/fileName.
                     * If the file already exists, the operation fails.
                     * If fileType is SQL and the filename ends with .gz, the contents are compressed.
                     */
                    uri: `gs://` + parsedBody.bucket_name + `/backups/backup-`.concat(utc).concat(`.gz`),

                    /**
                     * Databases from which the export is made.
                     * If fileType is SQL and no database is specified, all databases are exported.
                     * If fileType is CSV, you can optionally specify at most one database to export.
                     * If csvExportOptions.selectQuery also specifies the database, this field will be ignored.
                     **/
                    // databases: ['myDatabase']
                    // Options for exporting data as SQL statements.
                    // sqlExportOptions: {
                    //   /**
                    //    * Tables to export, or that were exported, from the specified database.
                    //    * If you specify tables, specify one and only one database. 
                    //    */
                    //   tables: config.tables,
                    //   // Export only schemas?
                    //   schemaOnly: config.schemaOnly
                    // }
                }
            },
            // Auth client
            auth: authClient
        };
        // Kick off export with requested arguments.
        sqladmin.instances.export(request, function (err, result) {
            if (err) {
                console.log(err);
            } else {
                console.log(result);
            }
            res.status(200).send("Command completed", err, result);
        });
    }
    initiateDatabaseExport();
};

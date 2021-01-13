REM This must be executed from within the VNet after the private endpoint was created and approved.
REM https://docs.microsoft.com/en-us/azure/search/search-indexer-howto-access-private

@ECHO OFF
SET COGNITIVESEARCHNAME=xxx
SET COGNITIVESEARCHADMINKEY=xxx
SET DATASOURCENAME=content-datasource
SET INDEXNAME=content-index
SET INDEXERNAME=content-indexer

ECHO List of all datasources:
curl -X GET "https://%COGNITIVESEARCHNAME%.search.windows.net/datasources?api-version=2020-06-30&$select=name" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%"
ECHO.
ECHO List of all indexes:
curl -X GET "https://%COGNITIVESEARCHNAME%.search.windows.net/indexes?api-version=2020-06-30&$select=name" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%"
ECHO.
ECHO List of all indexers:
curl -X GET "https://%COGNITIVESEARCHNAME%.search.windows.net/indexers?api-version=2020-06-30&$select=name" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%"

ECHO.
ECHO Creating data source...
curl -X PUT "https://%COGNITIVESEARCHNAME%.search.windows.net/datasources/%DATASOURCENAME%?api-version=2020-06-30" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%" --data-binary @azuresearch-storage-datasource.json

ECHO.
ECHO Creating index...
curl -X PUT "https://%COGNITIVESEARCHNAME%.search.windows.net/indexes/%INDEXNAME%?api-version=2020-06-30" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%" --data-binary @azuresearch-storage-index.json

ECHO.
ECHO Creating indexer...
curl -X PUT "https://%COGNITIVESEARCHNAME%.search.windows.net/indexers/%INDEXERNAME%?api-version=2020-06-30" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%" --data-binary @azuresearch-storage-indexer.json

ECHO.
ECHO Performing search...
curl -X GET "https://%COGNITIVESEARCHNAME%.search.windows.net/indexes/%INDEXNAME%/docs?api-version=2020-06-30&search=diversity&$select=metadata_storage_name" -H "Content-Type: application/json" -H "api-key: %COGNITIVESEARCHADMINKEY%"

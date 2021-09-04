curl -X PUT -H 'Content-Type: application/json' -d '
{
    "mappings": {
         "properties" : {
             "user_role" : {
                 "type" : "nested",
                 "properties" : {
                     "user_id" : { "type" : "long" },
                     "role_id" : { "type" : "long" }
                 }
             }
         }
    }
}' 'http://localhost:9200/logstash_resource'
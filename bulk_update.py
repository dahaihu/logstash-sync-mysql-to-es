import time
from datetime import datetime

from elasticsearch import Elasticsearch
from elasticsearch import helpers

es = Elasticsearch()

actions = [
    {
        "_index": "bulk-index",
        "_type": "_doc",
        "_id": j,
        "_source": {
            "any": "data" + str(j),
            "timestamp": datetime.now(),
        }
    }
    for j in range(0, 1000000)
]

if __name__ == '__main__':
    start = time.time()
    success, errors = helpers.bulk(es, actions)
    print(success, errors)
    print("cost time is ", time.time() - start)

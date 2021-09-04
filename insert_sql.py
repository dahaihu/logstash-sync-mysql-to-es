import time
import uuid

import pymysql.cursors

db = pymysql.connect(user="root", passwd="669193", db="sync_es")
db.autocommit(True)
conn = db.cursor()


def insert_resource():
    for i in range(10000):
        now = int(time.time())
        name = uuid.uuid4()
        conn.execute("""
          insert into `logstash_resource`
          (`name`, description, create_time, update_time, delete_time) 
          values('%s', '%s', %d, %d, 0);""" % (str(name), str(name), now, now))
        resource_id = conn.lastrowid
        for j in range(3):
            conn.execute(
                """insert into `resource_role`
                (user_id, resource_id, role_id, create_time, update_time, delete_time) 
                values(%d, %d, %d, %d, %d, 0);""" %
                (j + 1, resource_id, j + 1, now, now))


if __name__ == '__main__':
    insert_resource()

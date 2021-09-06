# 使用logstash从mysql同步数据到elasticsearch

## 单表同步

### 表结构

```sql
CREATE TABLE `sync_es.logstash_resource` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL COMMENT 'resource name',
  `description` varchar(100) NOT NULL COMMENT 'resource description',
  `create_time` bigint(20) NOT NULL COMMENT 'create_time',
  `update_time` bigint(20) NOT NULL COMMENT 'update_time',
  `delete_time` bigint(20) DEFAULT '0' COMMENT 'delete_time',
  PRIMARY KEY (`id`),
  KEY `update_time` (`update_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

### logstash 配置

```conf
input {
  jdbc {
    jdbc_driver_library => "/path-to-jar/mysql-connector-java-8.0.26.jar"
    jdbc_driver_class => "com.mysql.jdbc.Driver"
    jdbc_connection_string => "jdbc:mysql://localhost:3306/sync_es"
    jdbc_user => root
    jdbc_password => "123456"
    use_column_value => true
    tracking_column => "update_time"
    tracking_column_type => numeric
    record_last_run => true
    last_run_metadata_path => "latest_update_time.txt"
    statement => "SELECT * FROM logstash_resource where update_time >:sql_last_value;"
    schedule => "* * * * * *"
  }
}

filter {
    mutate {
      remove_field => ["@version", "@timestamp"]
    }
}

output {
  elasticsearch {
    document_id=> "%{id}"
    document_type => "doc"
    index => "logstash_resource"
    hosts => ["http://localhost:9200"]
  }
  stdout{
    codec => rubydebug
  }
}

```

### logstash 配置详解

配置中的如下项是关于`mysql`链接相关的配置。

```
 jdbc_driver_library => "/path-to-jar/mysql-connector-java-8.0.26.jar"
 jdbc_driver_class => "com.mysql.jdbc.Driver"
 jdbc_connection_string => "jdbc:mysql://localhost:3306/sync_es"
 jdbc_user => root
 jdbc_password => "123456"
```

配置中的如下项是表示使用`update_time`来记录上一次的更新时间，内容存储在`last_run_metadata_path
`里面。在每次调度的时候，会把`statement`之中的`:sql_last_value`替换为上次记录的值。调度完成之后，则会把此次运行的最大`update_time`更新到`last_run_metadata_path`之中以便下次调用; `tracking_column_type`在此场景下是`numeric`表示数值类型，另外还支持的类型是`datetime`。

```
use_column_value => true
tracking_column => "update_time"
tracking_column_type => "numeric"
record_last_run => true
last_run_metadata_path => "latest_update_time.txt"
```

`statement`中的是一个 sql 语句，`select`的内容会被存储到`elasticsearch`里面去。

```
statement => "SELECT * FROM logstash_resource where update_time >= :sql_last_value;"
```

`schedule`表示的是调度的信息，执行`statement`并把结果存储到`elasticsearch`的执行时机，这个里面表示的是每秒执行一次。

```
schedule => "* * * * * *"
```

## nested field 同步

`mysql`是存在一对多的场景的，比如存在一个用户对资源的角色表，每个资源是存在多个用户对此资源有权限的。用户对资源的角色信息如果需要存储到`elasticsearch`之中，就需要使用`nested field`了。

### 新增表结构

```sql
CREATE TABLE `sync_es.logstash_resource_role` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `resource_id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_resource` (`user_id`,`resource_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

### logstash 配置

```
input {
    jdbc {
    	jdbc_driver_library => "/path-to-jar/mysql-connector-java-8.0.26.jar"
        jdbc_driver_class => "com.mysql.jdbc.Driver"
        jdbc_connection_string => "jdbc:mysql://localhost:3306/sync_es"
        jdbc_user => root
        jdbc_password => "123456"
        clean_run => true
        use_column_value => true
        record_last_run => true
        tracking_column => "update_time"
        tracking_column_type => numeric
        last_run_metadata_path => "last_update_time.txt"
        schedule => "* * * * * *"
        statement => "
        SELECT
            logstash_resource.id AS id,
            logstash_resource.name AS name,
            logstash_resource.description AS description,
            logstash_resource.create_time AS create_time,
            logstash_resource.update_time AS update_time,
            logstash_resource.delete_time AS delete_time,
            logstash_resource_role.user_id AS user_id,
            logstash_resource_role.role_id AS role_id
        FROM logstash_resource LEFT JOIN logstash_resource_role
        ON logstash_resource.id = logstash_resource_role.resource_id WHERE logstash_resource.update_time >= :sql_last_value;"
   }
}

filter {
     aggregate {
        task_id => "%{id}"
        code => "
            map['id'] = event.get('id')
            map['name'] = event.get('name')
            map['description'] = event.get('description')
            map['create_time'] = event.get('create_time')
            map['update_time'] = event.get('update_time')
            map['delete_time'] = event.get('delete_time')
            map['user_role'] ||=[]
            if (event.get('user_id') != nil)
                map['user_role'].delete_if{|x| x['user_id'] == event.get('user_id')}
                map['user_role'] << {
                    'user_id' => event.get('user_id'),
                    'role_id' => event.get('role_id'),
                }
            end
            event.cancel()
        "
        push_previous_map_as_event => true
        timeout => 5
    }
}

output {
   stdout {
        #codec => json_lines
   }
        elasticsearch {
        hosts => ["127.0.0.1:9200"]
        index => "logstash_resource"
        document_id => "%{id}"
   }
}
```

`statement`执行的结果可以如下

```
+----+-------+-------------+-------------+-------------+-------------+---------+---------+
| id | name  | description | create_time | update_time | delete_time | user_id | role_id |
+----+-------+-------------+-------------+-------------+-------------+---------+---------+
|  1 | name1 | description |  1630744743 |  1630748902 |           0 |       1 |       2 |
|  1 | name1 | description |  1630744743 |  1630748902 |           0 |       2 |       3 |
|  2 | name2 | description |  1630744744 |  1630748902 |           0 |       3 |       3 |
+----+-------+-------------+-------------+-------------+-------------+---------+---------+
```

`aggregrate`的配置解析如下:

1. `push_previous_map_as_event => true`: `aggregate`插件每次碰到一个新的`id`，会把之前聚合的结果`map`作为一个`event`，存储到`elasticsearch`里面去。然后为这个新`id`创建一个`map`。
2. `timeout =>5`: 当有`5s`没有新的`event`，则会把最后一次聚合的结果`map`，存储到`elasticsearch`之中。
3. 原始的`event`并不会被处理，因为脚本的结尾执行了`event.cancel()`。

在执行`logstash`之前，需要通过如下方式创建好`mapping`

```shell
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
```

对于`statement`实例存储到`elasticsearch`的两条记录就如下:

```json
[
      {
        "_index": "logstash_resource",
        "_type": "_doc",
        "_id": "2",
        "_score": 1,
        "_source": {
          "description": "description",
          "update_time": 1630748902,
          "delete_time": 0,
          "create_time": 1630744744,
          "user_role": [
            {
              "user_id": 3,
              "role_id": 3
            }
          ],
          "name": "name2",
          "id": 2
        }
      },
      {
        "_index": "logstash_resource",
        "_type": "_doc",
        "_id": "1",
        "_score": 1,
        "_source": {
          "description": "description",
          "update_time": 1630748902,
          "delete_time": 0,
          "create_time": 1630744743,
          "user_role": [
            {
              "user_id": 2,
              "role_id": 3
            }
          ],
          "name": "name1",
          "id": 1
        }
      }
]
```

## logstash同步的问题

1. 如果`sql`使用的条件是`>`，假如此时的最大`update_time`是`1630744741`，而后续如果也有`update_time`是`1630744741`的数据插入进来，数据就不会插入到`elasticsearch`里面去；如果`sql`使用的条件是`>=`，那么下次执行的时候，数据记录中`update_time`为`1630744741`会再次同步。(这个`update_time`是一个`s`级的时间戳，要在一定程度上缓解这个问题可以使用`ms`级的时间戳)
2. nested field数据更新，需要由`logstash_resource_role`表反映到`logstash_resource`里面去，因为需要由`update_time`才会触发对资源的数据以及角色的数据进行更新, ，这个就会增加业务逻辑之间的复杂度了。。
3. 本文所有代码都在项目[logstash-sync-mysql-to-es](https://github.com/dahaihu/logstash-sync-mysql-to-es)，觉得有用的同学可以给本文点赞呀，还可以`star`下项目。

### 参考文献

[1] https://www.elastic.co/guide/en/logstash/current/plugins-inputs-jdbc.html#plugins-inputs-jdbc-record_last_run

[2] https://www.elastic.co/guide/en/logstash/current/plugins-filters-aggregate.html#plugins-filters-aggregate
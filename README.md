# 使用logstash从mysql同步数据到elasticsearch

## 单表同步

使用到的表结构如下

```sql
CREATE TABLE `logstash_resource` (
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

logstash需要使用的配置如下

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

配置中的如下项是关于`mysql`链接相关的配置。

```
 jdbc_driver_library => "/path-to-jar/mysql-connector-java-8.0.26.jar"
 jdbc_driver_class => "com.mysql.jdbc.Driver"
 jdbc_connection_string => "jdbc:mysql://localhost:3306/sync_es"
 jdbc_user => root
 jdbc_password => "123456"
```

配置中的如下项是表示使用`update_time`来记录上一次的更新时间，内容存储在`last_run_metadata_path`里面。在每次调度的时候，会把上次记录的值替换为`statement`之中的`:sql_last_value`。

```
use_column_value => true
tracking_column => "update_time"
tracking_column_type => numeric
record_last_run => true
last_run_metadata_path => "latest_update_time.txt"
```

`statement`中的是一个 sql 语句，`select`的内容会被存储到`elasticsearch`里面去。

```
statement => "SELECT * FROM logstash_resource where update_time >= :sql_last_value;"
```

`schedule`表示的是调度的信息，执行`statement`并把结果存储到`elasticsearch`的执行实际，这个里面表示的是每秒执行一次。

```
schedule => "* * * * * *"
```

## nested field 同步

比如有一个用户对资源的角色表，需要用户按照对资源的角色进行搜索，这个时候需要使用`nested field`。如何将这个一对多的关系同步到`elasticsearch`之中呢？

新增的表结构如下

```sql
CREATE TABLE `logstash_resource_role` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `resource_id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `create_time` bigint(20) NOT NULL COMMENT 'create_time',
  `update_time` bigint(20) NOT NULL COMMENT 'update_time',
  `delete_time` bigint(20) DEFAULT '0' COMMENT 'delete_time',
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_resource` (`user_id`,`resource_id`),
  KEY `update_time` (`update_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

可以按照如下配置进行。`logstash_resource`表中除了有资源对应的信息，还有用户对该资源的角色信息。

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



## 问题

1. 这种更新有一个问题，如果`sql`使用的条件是`>`，此时的最大`update_time`假如是`1630744741`，而后续如果也有`update_time`是`1630744741`的数据插入进来，数据就不会插入到`elasticsearch`里面去；如果`sql`使用的条件是`>=`，那么下次执行的时候，数据记录中`update_time`为`1630744741`会再次同步。
2. nested field数据更新，需要由`logstash_resource_role`表反映到`logstash_resource`里面去，因为需要由`update_time`才会触发对资源的数据以及角色的数据进行更新。

[1] https://www.elastic.co/guide/en/logstash/current/plugins-inputs-jdbc.html#plugins-inputs-jdbc-record_last_run

[2] https://www.elastic.co/guide/en/logstash/current/plugins-filters-aggregate.html#plugins-filters-aggregate


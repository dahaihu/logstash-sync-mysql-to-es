CREATE TABLE `sync_es.logstash_resource_role` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `resource_id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_resource` (`user_id`,`resource_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



create table `sync_es.logstash_resource` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL COMMENT 'resource name',
    `description` VARCHAR(100) NOT NULL COMMENT 'resource description',
    `create_time` BIGINT(20) NOT NULL COMMENT 'create_time',
    `update_time` BIGINT(20) NOT NULL COMMENT 'update_time',
    `delete_time` BIGINT(20) DEFAULT 0 COMMENT 'delete_time',
    PRIMARY KEY ( `id` ),
    KEY `update_time` (update_time)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

insert into sync_es.logstash_resource(name, description, create_time, update_time)
values
('name1', 'description', 1630744743, 1630748902),
('name2', 'description', 1630744744, 1630748902);

insert into sync_es.logstash_resource_role(user_id, resource_id, role_id)
values(1, 1, 2), (2, 1, 3), (3, 2, 3);


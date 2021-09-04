CREATE TABLE `logstash_resource_role`(
    `id` INT UNSIGNED AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `resource_id` INT NOT NULL,
    `role_id` INT NOT NULL,
    `create_time` BIGINT(20) NOT NULL COMMENT 'create_time',
    `update_time` BIGINT(20) NOT NULL COMMENT 'update_time',
    `delete_time` BIGINT(20) DEFAULT 0 COMMENT 'delete_time',
    PRIMARY KEY ( `id` ),
    UNIQUE KEY `user_resource` (user_id, resource_id),
    KEY `update_time` (update_time)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;



create table `logstash_resource` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL COMMENT 'resource name',
    `description` VARCHAR(100) NOT NULL COMMENT 'resource description',
    `create_time` BIGINT(20) NOT NULL COMMENT 'create_time',
    `update_time` BIGINT(20) NOT NULL COMMENT 'update_time',
    `delete_time` BIGINT(20) DEFAULT 0 COMMENT 'delete_time',
    PRIMARY KEY ( `id` ),
    KEY `update_time` (update_time)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;


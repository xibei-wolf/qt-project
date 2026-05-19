-- ============================================================================
-- 青云志愿服务队管理系统 - 数据库架构定义 (MySQL 8.0+)
-- 设计原则：混合位图缓存方案，兼顾高性能筛选与 QML 前端展示便利性
-- ============================================================================

-- 创建数据库
CREATE DATABASE IF NOT EXISTS qinyun DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE qinyun;

-- ============================================================================
-- 1. roles（角色表）
-- 系统 RBAC 权限模型的根基，角色层级 10/20/30/40 决定数据可见范围
-- ============================================================================
CREATE TABLE roles (
    id          SMALLINT UNSIGNED  NOT NULL COMMENT '角色ID: 10=带队老师, 20=队长, 30=部长, 40=普通队员',
    name        VARCHAR(32)        NOT NULL COMMENT '角色名称',
    level       TINYINT UNSIGNED   NOT NULL UNIQUE COMMENT '权限层级，数值越小权限越高（10 > 20 > 30 > 40）',
    description TEXT               NULL     COMMENT '角色职责描述',
    permissions JSON               NOT NULL COMMENT '细粒度权限位标记，如 {"view_all_dept":true,"publish_activity":true}',
    created_at  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='角色权限表';

-- ============================================================================
-- 2. departments（部门表）
-- 5 个固定部门：策划部 / 外联部 / 办公室 / 宣传部 / 云教室
-- ============================================================================
CREATE TABLE departments (
    id          SMALLINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    name        VARCHAR(64)        NOT NULL COMMENT '部门名称',
    code        VARCHAR(32)        NOT NULL UNIQUE COMMENT '部门代号，如 planning / liaison / office / publicity / cloud_classroom',
    description TEXT               NULL     COMMENT '部门职能描述',
    sort_order  TINYINT UNSIGNED   NOT NULL DEFAULT 0 COMMENT '前端展示排序权重',
    created_at  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='部门表';

-- ============================================================================
-- 3. users（用户表）
-- 核心用户实体。role_id + department_id 共同决定用户的组织身份与数据访问边界。
-- ============================================================================
CREATE TABLE users (
    id              INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    student_id      VARCHAR(32)       NOT NULL COMMENT '学号，唯一标识',
    name            VARCHAR(64)       NOT NULL COMMENT '真实姓名',
    password_hash   VARCHAR(255)      NOT NULL COMMENT 'BCrypt 密码哈希',
    phone           VARCHAR(20)       NULL     COMMENT '手机号',
    email           VARCHAR(128)      NULL     COMMENT '邮箱',
    avatar_url      VARCHAR(512)      NULL     COMMENT '头像地址',
    department_id   SMALLINT UNSIGNED NULL     COMMENT '所属部门ID（带队老师、队长可为 NULL）',
    role_id         SMALLINT UNSIGNED NOT NULL COMMENT '角色ID，决定权限层级',
    status          TINYINT UNSIGNED  NOT NULL DEFAULT 1 COMMENT '状态: 1=正常, 0=禁用, 2=已毕业',
    last_login_at   DATETIME          NULL     COMMENT '最后登录时间',
    created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_student_id (student_id),
    INDEX idx_department (department_id),
    INDEX idx_role (role_id),
    INDEX idx_status (status),
    INDEX idx_phone (phone),
    CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户表';

-- ============================================================================
-- 4. course_records（课程记录表 —— 结构化存储）
-- 存储每门课的原始语义信息，供 QML 前端展示课表详情。
-- 这是"混合方案"的 A 面：保留完整课程语义，不做位图拍平。
--
-- 字段说明：
--   day_of_week : 1=周一 ... 5=周五
--   period_start: 第几大节开始（1-5）
--   period_count: 连续几大节（通常 1 或 2）
--   start_week  : 课程开始周（1-20）
--   end_week    : 课程结束周（1-20）
--   week_type   : 0=每周都上, 1=仅单周, 2=仅双周
--
-- 示例：高等数学，周一第1-2节，1-16周，每周都上
--   day_of_week=1, period_start=1, period_count=2, start_week=1, end_week=16, week_type=0
-- 示例：体育课，周三第5节，1-16周，仅双周
--   day_of_week=3, period_start=5, period_count=1, start_week=1, end_week=16, week_type=2
-- ============================================================================
CREATE TABLE course_records (
    id              INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    user_id         INT UNSIGNED      NOT NULL COMMENT '所属用户',
    course_name     VARCHAR(128)      NOT NULL DEFAULT '' COMMENT '课程名称，如"高等数学"',
    teacher_name    VARCHAR(64)       NOT NULL DEFAULT '' COMMENT '任课教师',
    classroom       VARCHAR(128)      NOT NULL DEFAULT '' COMMENT '上课地点',
    day_of_week     TINYINT UNSIGNED  NOT NULL COMMENT '星期几: 1=周一, 2=周二, 3=周三, 4=周四, 5=周五',
    period_start    TINYINT UNSIGNED  NOT NULL COMMENT '开始大节号: 1-5',
    period_count    TINYINT UNSIGNED  NOT NULL DEFAULT 1 COMMENT '连续大节数: 通常1或2',
    start_week      TINYINT UNSIGNED  NOT NULL COMMENT '起始教学周: 1-20',
    end_week        TINYINT UNSIGNED  NOT NULL COMMENT '结束教学周: 1-20',
    week_type       TINYINT UNSIGNED  NOT NULL DEFAULT 0 COMMENT '单双周类型: 0=每周, 1=仅单周, 2=仅双周',
    created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_user_id (user_id),
    INDEX idx_day_period (day_of_week, period_start),
    INDEX idx_week_range (start_week, end_week),
    CONSTRAINT fk_course_records_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    -- 业务约束：防止同一用户在同一时段录入重复课程
    CONSTRAINT chk_period_range CHECK (period_start >= 1 AND period_start <= 5),
    CONSTRAINT chk_day_range CHECK (day_of_week >= 1 AND day_of_week <= 5),
    CONSTRAINT chk_week_range CHECK (start_week >= 1 AND start_week <= 20 AND end_week >= start_week AND end_week <= 20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='课程记录表（结构化存储，供QML展示课程详情）';

-- ============================================================================
-- 5. schedules（课表位图表 —— 按周缓存）
-- 这是"混合方案"的 B 面：为每位用户的每一周预计算 32 位位图，
-- 支持用单条位运算 WHERE 子句完成"无课队员筛选"，时间复杂度 O(1)。
--
-- 位图编码规则（32 位无符号整数，INT UNSIGNED）：
--   bit_index = (day_of_week - 1) * 5 + (period - 1)
--   1 = 该时段有课（忙碌），0 = 该时段空闲
--
-- 位布局表：
--   bit 0-4   : 周一第1-5节
--   bit 5-9   : 周二第1-5节
--   bit 10-14 : 周三第1-5节
--   bit 15-19 : 周四第1-5节
--   bit 20-24 : 周五第1-5节
--   bit 25-31 : 保留（始终为 0）
--
-- 示例：用户周三第3-4节有课 → bit 12 和 bit 13 置 1 → 0x3000
-- 筛选时：(schedule_bitmask & activity_time_mask) = 0 表示该用户在该时段完全空闲
--
-- 本表数据由 sp_recompute_user_schedule() 存储过程在课程变更时自动重建。
-- ============================================================================
CREATE TABLE schedules (
    id          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    user_id     INT UNSIGNED    NOT NULL COMMENT '用户ID',
    week_number TINYINT UNSIGNED NOT NULL COMMENT '教学周编号: 1-20',
    bitmask     INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT '32位空闲位图: 1=有课/忙碌, 0=空闲',
    updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_user_week (user_id, week_number),
    INDEX idx_week_mask (week_number, bitmask),
    CONSTRAINT fk_schedules_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='课表位图表（按周缓存，支持O(1)位运算筛选）';

-- ============================================================================
-- 6. activities（活动信息表）
-- 管理员/队长发布活动时，指定活动所在教学周 + 占用时段的位图掩码。
-- ============================================================================
CREATE TABLE activities (
    id              INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    title           VARCHAR(256)      NOT NULL COMMENT '活动名称',
    description     TEXT              NULL     COMMENT '活动描述/注意事项',
    location        VARCHAR(256)      NOT NULL DEFAULT '' COMMENT '活动地点',
    organizer_id    INT UNSIGNED      NOT NULL COMMENT '发布人用户ID',
    department_id   SMALLINT UNSIGNED NULL     COMMENT '主办部门ID（NULL=全队活动）',
    activity_week   TINYINT UNSIGNED  NOT NULL COMMENT '活动所在教学周: 1-20',
    time_mask       INT UNSIGNED      NOT NULL COMMENT '活动占用时段位图: 1=该时段需要人手, 0=不需要',
    max_participants SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '最大参与人数，0=不限',
    sign_deadline   DATETIME          NULL     COMMENT '报名截止时间',
    status          TINYINT UNSIGNED  NOT NULL DEFAULT 0 COMMENT '状态: 0=草稿, 1=报名中, 2=已截止, 3=进行中, 4=已完成, 5=已取消',
    created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_organizer (organizer_id),
    INDEX idx_department_week (department_id, activity_week),
    INDEX idx_status_week (status, activity_week),
    INDEX idx_week (activity_week),
    CONSTRAINT fk_activities_organizer FOREIGN KEY (organizer_id) REFERENCES users(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_activities_department FOREIGN KEY (department_id) REFERENCES departments(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_activity_week CHECK (activity_week >= 1 AND activity_week <= 20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='活动信息表';

-- ============================================================================
-- 7. activity_members（活动排班录用表）
-- 记录被录用参加活动的队员名单、录用来源、签到状态。
-- 防止同一个人被重复录用同一活动（UNIQUE 约束）。
-- ============================================================================
CREATE TABLE activity_members (
    id              INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    activity_id     INT UNSIGNED      NOT NULL COMMENT '活动ID',
    user_id         INT UNSIGNED      NOT NULL COMMENT '队员用户ID',
    assign_type     TINYINT UNSIGNED  NOT NULL DEFAULT 0 COMMENT '录用方式: 0=手动指定, 1=智能排班, 2=自主报名, 3=替补递补',
    sign_in_status  TINYINT UNSIGNED  NOT NULL DEFAULT 0 COMMENT '签到状态: 0=未签到, 1=已签到, 2=迟到, 3=请假',
    sign_in_time    DATETIME          NULL     COMMENT '签到时间',
    remark          VARCHAR(512)      NULL     COMMENT '备注（如请假原因）',
    created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_activity_user (activity_id, user_id),
    INDEX idx_user_sign (user_id, sign_in_status),
    INDEX idx_activity_sign (activity_id, sign_in_status),
    CONSTRAINT fk_am_activity FOREIGN KEY (activity_id) REFERENCES activities(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_am_user FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='活动排班录用表';

-- ============================================================================
-- UDF 辅助函数：将 (星期几, 开始节次, 节数) 转换为 32 位位图掩码
-- 用于存储过程批量计算课表位图
-- ============================================================================
DELIMITER //

CREATE FUNCTION fn_period_bitmask(
    p_day           TINYINT UNSIGNED,  -- 1=周一 ... 5=周五
    p_period_start  TINYINT UNSIGNED,  -- 开始大节 1-5
    p_period_count  TINYINT UNSIGNED   -- 连续大节数
)
RETURNS INT UNSIGNED
DETERMINISTIC
READS SQL DATA
COMMENT '将(星期几, 第几节, 节数)转为32位位图掩码'
BEGIN
    DECLARE v_bitmask INT UNSIGNED DEFAULT 0;
    DECLARE v_i TINYINT UNSIGNED DEFAULT 0;

    WHILE v_i < p_period_count DO
        SET v_bitmask = v_bitmask | (1 << ((p_day - 1) * 5 + (p_period_start - 1 + v_i)));
        SET v_i = v_i + 1;
    END WHILE;

    RETURN v_bitmask;
END //

-- ============================================================================
-- 存储过程：为用户重算指定教学周范围内的所有课表位图
-- 调用时机：用户新增/修改/删除课程记录后，由应用层调用此过程刷新缓存
--
-- 核心逻辑：
--   对每一周 w（1-20），遍历该用户所有 course_records：
--     条件 1: start_week <= w <= end_week          → 课程在有效周数内
--     条件 2: week_type=0 OR (w%2=1 AND week_type=1) OR (w%2=0 AND week_type=2)
--                                                  → 匹配单双周规则
--   将满足条件的课程位图做 BIT_OR 聚合，写入 schedules 表
-- ============================================================================
CREATE PROCEDURE sp_recompute_user_schedule(
    IN p_user_id        INT UNSIGNED,
    IN p_total_weeks    TINYINT UNSIGNED
)
COMMENT '重算某用户所有周的课表位图缓存'
BEGIN
    DECLARE v_week TINYINT UNSIGNED DEFAULT 1;
    DECLARE v_bitmask INT UNSIGNED DEFAULT 0;

    -- 逐周计算
    WHILE v_week <= p_total_weeks DO
        -- 聚合所有匹配该周的课程位图
        SELECT COALESCE(
            BIT_OR(
                fn_period_bitmask(cr.day_of_week, cr.period_start, cr.period_count)
            ), 0
        ) INTO v_bitmask
        FROM course_records cr
        WHERE cr.user_id = p_user_id
          AND cr.start_week <= v_week
          AND cr.end_week >= v_week
          AND (
              cr.week_type = 0
              OR (cr.week_type = 1 AND MOD(v_week, 2) = 1)   -- 单周
              OR (cr.week_type = 2 AND MOD(v_week, 2) = 0)   -- 双周
          );

        -- UPSERT: 不存在则插入，存在则更新
        INSERT INTO schedules (user_id, week_number, bitmask)
        VALUES (p_user_id, v_week, v_bitmask)
        ON DUPLICATE KEY UPDATE bitmask = v_bitmask, updated_at = NOW();

        SET v_week = v_week + 1;
    END WHILE;
END //

-- ============================================================================
-- 存储过程：批量重算所有用户的课表位图
-- 调用时机：学期初始或系统维护时全量刷新
-- ============================================================================
CREATE PROCEDURE sp_recompute_all_schedules(
    IN p_total_weeks TINYINT UNSIGNED
)
COMMENT '批量重算所有用户的课表位图缓存'
BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_uid INT UNSIGNED;
    DECLARE cur CURSOR FOR SELECT id FROM users WHERE status = 1;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur;

    user_loop: LOOP
        FETCH cur INTO v_uid;
        IF v_done THEN
            LEAVE user_loop;
        END IF;
        CALL sp_recompute_user_schedule(v_uid, p_total_weeks);
    END LOOP;

    CLOSE cur;
END //

DELIMITER ;

-- ============================================================================
-- 触发器：课程记录变更后自动刷新该用户的位图缓存
-- 注：生产环境建议用应用层异步任务代替触发器，避免写放大
-- ============================================================================
DELIMITER //

CREATE TRIGGER trg_course_records_after_insert
AFTER INSERT ON course_records FOR EACH ROW
BEGIN
    CALL sp_recompute_user_schedule(NEW.user_id, 20);
END //

CREATE TRIGGER trg_course_records_after_update
AFTER UPDATE ON course_records FOR EACH ROW
BEGIN
    CALL sp_recompute_user_schedule(NEW.user_id, 20);
END //

CREATE TRIGGER trg_course_records_after_delete
AFTER DELETE ON course_records FOR EACH ROW
BEGIN
    CALL sp_recompute_user_schedule(OLD.user_id, 20);
END //

DELIMITER ;

-- ============================================================================
-- 核心查询示例（供后端 C++ 参考，不创建为视图）
-- ============================================================================

-- 【查询1：智能排班 —— 筛选某活动第N周完全空闲的普通队员】
-- 说明：活动 time_mask 的 1 位代表活动占用的时段。
--       (s.bitmask & mask) = 0 意味着队员在这些时段全部空闲（没有课程冲突）。
--
-- SELECT u.id, u.name, u.student_id, d.name AS dept_name
-- FROM users u
-- INNER JOIN schedules s ON u.id = s.user_id
-- LEFT JOIN departments d ON u.department_id = d.id
-- WHERE s.week_number = :activity_week
--   AND (s.bitmask & :time_mask) = 0     -- 核心：位运算无课筛选
--   AND u.role_id = 40                    -- 仅普通队员
--   AND u.status = 1                      -- 仅正常状态
--   AND u.department_id = :dept_id        -- 可选：限定部门
-- ORDER BY u.student_id;

-- 【查询2：一键排班 —— 自动将筛选出的队员录入活动】
-- INSERT INTO activity_members (activity_id, user_id, assign_type, sign_in_status)
-- SELECT :activity_id, u.id, 1, 0
-- FROM users u
-- INNER JOIN schedules s ON u.id = s.user_id
-- WHERE s.week_number = :week
--   AND (s.bitmask & :mask) = 0
--   AND u.role_id = 40
--   AND u.status = 1
--   AND NOT EXISTS (
--     SELECT 1 FROM activity_members am
--     WHERE am.activity_id = :activity_id AND am.user_id = u.id
--   )
-- LIMIT :max_count;

-- 【查询3：查看某队员某周的课表详情（供 QML 展示）】
-- SELECT cr.course_name, cr.teacher_name, cr.classroom,
--        cr.day_of_week, cr.period_start, cr.period_count,
--        cr.start_week, cr.end_week, cr.week_type
-- FROM course_records cr
-- WHERE cr.user_id = :user_id
--   AND cr.start_week <= :week
--   AND cr.end_week >= :week
--   AND (cr.week_type = 0
--        OR (cr.week_type = 1 AND MOD(:week, 2) = 1)
--        OR (cr.week_type = 2 AND MOD(:week, 2) = 0))
-- ORDER BY cr.day_of_week, cr.period_start;

-- 【查询4：查看某队员某周的位图无课状态（供 QML 可视化网格）】
-- SELECT s.bitmask
-- FROM schedules s
-- WHERE s.user_id = :user_id AND s.week_number = :week;

-- ============================================================================
-- 种子数据：角色和部门的初始数据
-- ============================================================================

-- 角色种子数据
INSERT INTO roles (id, name, level, description, permissions) VALUES
(10, '带队老师', 10, '系统最高权限，可查看所有部门和人员数据',
 '{"view_all_dept":true,"manage_all_users":true,"publish_activity":true,"auto_schedule":true,"audit_activity":true,"export_data":true}'),
(20, '队长', 20, '全队统筹权限，活动发布和一键排班',
 '{"view_all_dept":true,"manage_team_members":true,"publish_activity":true,"auto_schedule":true,"audit_activity":true}'),
(30, '部长', 30, '部门管理权限，管理本部门成员和排班',
 '{"view_own_dept":true,"manage_dept_members":true,"publish_dept_activity":true,"view_dept_schedule":true}'),
(40, '普通队员', 40, '基础权限，维护个人信息和课表，查看被录用活动',
 '{"edit_profile":true,"upload_schedule":true,"view_own_activities":true,"apply_activity":true}');

-- 部门种子数据
INSERT INTO departments (name, code, description, sort_order) VALUES
('策划部',   'planning',       '负责活动策划、方案设计与审核',     1),
('外联部',   'liaison',        '负责对外联络、资源对接与合作洽谈', 2),
('办公室',   'office',         '负责行政事务、档案管理与物资统筹', 3),
('宣传部',   'publicity',      '负责活动宣传、新媒体运营与物料设计', 4),
('云教室',   'cloud_classroom','负责线上支教、课程录制与远程教学', 5);

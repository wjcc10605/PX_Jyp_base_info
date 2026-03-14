-- 第一张表：截止到某一时间点的各层历史累计用户数
-- 参数说明：
-- @end_date: 截止日期，格式为'yyyymmdd'，例如'20260314'

WITH 
-- 第一层：平台整体用户量
level1_users AS (
    SELECT 
        user_id
    FROM yj_new_dw.dwd_pxb7_user_user_df
    WHERE ds = MAX_PT('yj_new_dw.dwd_pxb7_user_user_df')
    AND TO_CHAR(regist_time,'yyyymmdd') <= '${end_date}'
),

-- 第二层：访问过金羊皮（带有金融标签）且访问过商品的用户
level2_users AS (
    SELECT 
        DISTINCT u.user_id
    FROM level1_users u
    -- 带有金融标签
    JOIN yj_new_dw.dwd_pxb7_user_user_extend_info_df ext
        ON u.user_id = ext.user_id
        AND ext.ds = MAX_PT('yj_new_dw.dwd_pxb7_user_user_extend_info_df')
        AND GET_JSON_OBJECT(ext.extra,'$.financeUserTag') = 1
    -- 访问过商品
    JOIN yj_new_dw.dws_gio_event_di event
        ON u.user_id = event.merge_id
        AND event.ds <= '${end_date}'
        AND event.event_key IN ('productOnshow', 'productDetailPageView')
),

-- 第三层：在第二层基础上有过下单行为的用户
level3_users AS (
    SELECT 
        DISTINCT l2.user_id
    FROM level2_users l2
    JOIN yj_new_dw.dws_pxb7_trade_order_item_summary_df ord
        ON l2.user_id = ord.buyer_id
        AND ord.ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
        AND TO_CHAR(ord.order_time,'yyyymmdd') <= '${end_date}'
),

-- 第四层：在第三层基础上有过支付行为的用户
level4_users AS (
    SELECT 
        DISTINCT l3.user_id
    FROM level3_users l3
    JOIN yj_new_dw.dws_pxb7_trade_order_item_summary_df ord
        ON l3.user_id = ord.buyer_id
        AND ord.ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
        AND TO_CHAR(ord.order_time,'yyyymmdd') <= '${end_date}'
        AND ord.order_item_status NOT IN ('待支付','已取消')
),

-- 第五层：在第四层基础上有过完单行为的用户
level5_users AS (
    SELECT 
        DISTINCT l4.user_id
    FROM level4_users l4
    JOIN yj_new_dw.dws_pxb7_trade_order_item_summary_df ord
        ON l4.user_id = ord.buyer_id
        AND ord.ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
        AND TO_CHAR(ord.order_time,'yyyymmdd') <= '${end_date}'
        AND ord.order_item_status_code = 4
)

-- 输出各层用户数
SELECT 
    '平台整体用户' AS user_level,
    COUNT(*) AS user_count
FROM level1_users
UNION ALL
SELECT 
    '访问过金羊皮且访问过商品的用户' AS user_level,
    COUNT(*) AS user_count
FROM level2_users
UNION ALL
SELECT 
    '有过下单行为的用户' AS user_level,
    COUNT(*) AS user_count
FROM level3_users
UNION ALL
SELECT 
    '有过支付行为的用户' AS user_level,
    COUNT(*) AS user_count
FROM level4_users
UNION ALL
SELECT 
    '有过完单行为的用户' AS user_level,
    COUNT(*) AS user_count
FROM level5_users;


-- 第二张表：各时间段各环节的新增用户数
-- 参数说明：
-- @start_date: 开始日期，格式为'yyyymmdd'，例如'20260101'
-- @end_date: 结束日期，格式为'yyyymmdd'，例如'20260314'

WITH 
-- 生成日期序列
date_series AS (
    SELECT 
        TO_CHAR(DATEADD(day, seq, TO_DATE('${start_date}', 'yyyymmdd')), 'yyyymmdd') AS date_id
    FROM (SELECT 0 AS seq UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)
    WHERE DATEADD(day, seq, TO_DATE('${start_date}', 'yyyymmdd')) <= TO_DATE('${end_date}', 'yyyymmdd')
),

-- 第一层：平台整体用户（按注册日期）
level1_daily AS (
    SELECT 
        TO_CHAR(regist_time, 'yyyymmdd') AS date_id,
        user_id
    FROM yj_new_dw.dwd_pxb7_user_user_df
    WHERE ds = MAX_PT('yj_new_dw.dwd_pxb7_user_user_df')
    AND TO_CHAR(regist_time, 'yyyymmdd') BETWEEN '${start_date}' AND '${end_date}'
),

-- 第二层：访问过金羊皮（带有金融标签）且访问过商品的用户（按首次满足条件日期）
level2_daily AS (
    SELECT 
        user_id,
        MIN(TO_CHAR(event_time, 'yyyymmdd')) AS first_date
    FROM (
        SELECT 
            u.user_id,
            event.event_time
        FROM yj_new_dw.dwd_pxb7_user_user_df u
        JOIN yj_new_dw.dwd_pxb7_user_user_extend_info_df ext
            ON u.user_id = ext.user_id
            AND ext.ds = MAX_PT('yj_new_dw.dwd_pxb7_user_user_extend_info_df')
            AND GET_JSON_OBJECT(ext.extra,'$.financeUserTag') = 1
        JOIN yj_new_dw.dws_gio_event_di event
            ON u.user_id = event.merge_id
            AND event.event_key IN ('productOnshow', 'productDetailPageView')
            AND TO_CHAR(event.event_time, 'yyyymmdd') BETWEEN '${start_date}' AND '${end_date}'
    ) t
    GROUP BY user_id
),

-- 第三层：有过下单行为的用户（按首次下单日期）
level3_daily AS (
    SELECT 
        buyer_id AS user_id,
        MIN(TO_CHAR(order_time, 'yyyymmdd')) AS first_date
    FROM yj_new_dw.dws_pxb7_trade_order_item_summary_df
    WHERE ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
    AND TO_CHAR(order_time, 'yyyymmdd') BETWEEN '${start_date}' AND '${end_date}'
    GROUP BY buyer_id
),

-- 第四层：有过支付行为的用户（按首次支付日期）
level4_daily AS (
    SELECT 
        buyer_id AS user_id,
        MIN(TO_CHAR(order_time, 'yyyymmdd')) AS first_date
    FROM yj_new_dw.dws_pxb7_trade_order_item_summary_df
    WHERE ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
    AND TO_CHAR(order_time, 'yyyymmdd') BETWEEN '${start_date}' AND '${end_date}'
    AND order_item_status NOT IN ('待支付','已取消')
    GROUP BY buyer_id
),

-- 第五层：有过完单行为的用户（按首次完单日期）
level5_daily AS (
    SELECT 
        buyer_id AS user_id,
        MIN(TO_CHAR(order_time, 'yyyymmdd')) AS first_date
    FROM yj_new_dw.dws_pxb7_trade_order_item_summary_df
    WHERE ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
    AND TO_CHAR(order_time, 'yyyymmdd') BETWEEN '${start_date}' AND '${end_date}'
    AND order_item_status_code = 4
    GROUP BY buyer_id
)

-- 输出各时间段各环节的新增用户数
SELECT 
    d.date_id AS 日期,
    COUNT(DISTINCT l1.user_id) AS 新增平台用户,
    COUNT(DISTINCT l2.user_id) AS 新增访问金羊皮且访问商品用户,
    COUNT(DISTINCT l3.user_id) AS 新增下单用户,
    COUNT(DISTINCT l4.user_id) AS 新增支付用户,
    COUNT(DISTINCT l5.user_id) AS 新增完单用户
FROM date_series d
LEFT JOIN level1_daily l1 ON d.date_id = l1.date_id
LEFT JOIN level2_daily l2 ON d.date_id = l2.first_date
LEFT JOIN level3_daily l3 ON d.date_id = l3.first_date
LEFT JOIN level4_daily l4 ON d.date_id = l4.first_date
LEFT JOIN level5_daily l5 ON d.date_id = l5.first_date
GROUP BY d.date_id
ORDER BY d.date_id;
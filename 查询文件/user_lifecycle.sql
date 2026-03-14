-- 用户生命周期表查询
-- 基于知识库中的实际表结构
-- 一阶：没有产生过交易
-- 二阶：有过1单交易
-- 三阶：有过2单以上交易，且不属于四阶和五阶
-- 四阶：有过交易但超过6个月没有交易
-- 五阶：有过交易但超过1年没有交易

-- 使用的表：
-- 用户表: yj_new_dw.dwd_pxb7_user_user_df (字段: user_id, regist_time)
-- 订单表: yj_new_dw.dws_pxb7_trade_order_item_summary_df (字段: order_time, buyer_id, order_item_status_code)
-- 订单状态: order_item_status_code = 4 表示已成交(完单)

WITH user_order_stats AS (
    SELECT
        buyer_id AS user_id,
        COUNT(*) AS order_count,
        MAX(order_time) AS last_order_time
    FROM
        yj_new_dw.dws_pxb7_trade_order_item_summary_df
    WHERE
        ds = '${bizdate}'  -- 数据分区，按日期分区
        AND order_item_status_code = 4  -- 已成交(完单)
    GROUP BY
        buyer_id
)

SELECT
    u.user_id,
    u.regist_time,
    COALESCE(uos.order_count, 0) AS order_count,
    uos.last_order_time,
    CASE
        WHEN uos.user_id IS NOT NULL AND DATE_DIFF(CURRENT_DATE, uos.last_order_time, DAY) > 365 THEN 5
        WHEN uos.user_id IS NOT NULL AND DATE_DIFF(CURRENT_DATE, uos.last_order_time, DAY) > 180 THEN 4
        WHEN uos.user_id IS NOT NULL AND uos.order_count > 2 THEN 3
        WHEN uos.user_id IS NOT NULL AND uos.order_count = 1 THEN 2
        ELSE 1
    END AS lifecycle_stage
FROM
    yj_new_dw.dwd_pxb7_user_user_df u
LEFT JOIN
    user_order_stats uos ON u.user_id = uos.user_id
WHERE
    u.ds = '${bizdate}'  -- 用户表的分区
ORDER BY
    u.user_id;

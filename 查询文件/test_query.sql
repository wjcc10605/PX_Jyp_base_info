-- 订单转化漏斗分析
WITH user_journey AS (
    SELECT 
        merge_id,
        MAX(CASE WHEN event_key = 'productOnshow' AND page_name IN ('商品列表页面','搜索结果页') THEN 1 ELSE 0 END) AS 商品列表浏览,
        MAX(CASE WHEN event_key = 'productDetailPageView' THEN 1 ELSE 0 END) AS 商详页浏览,
        MAX(CASE WHEN event_key = 'productDetailClick' AND page_name = '商品详情页面' AND pit_name IN ('咨询','立即购买','还价') THEN 1 ELSE 0 END) AS 高意向点击
    FROM yj_new_dw.dws_gio_event_di
    WHERE ds BETWEEN '20260123' AND '20260129'
    AND data_source_id IN ('PC','H5','Android')
    AND event_key NOT IN ('$ma_channel_touch','sellerContractSigned','buyerContractSigned')
    AND NOT (event_key = 'flowOnshow' AND pit_name = '返回顶部')
    GROUP BY merge_id
),
order_data AS (
    SELECT 
        buyer_id,
        MAX(CASE WHEN order_item_status_code IS NOT NULL THEN 1 ELSE 0 END) AS is_order,
        MAX(CASE WHEN order_item_status NOT IN ('待支付','已取消') THEN 1 ELSE 0 END) AS is_pay,
        MAX(CASE WHEN order_item_status_code = 4 THEN 1 ELSE 0 END) AS is_complete
    FROM yj_new_dw.dws_pxb7_trade_order_item_summary_df
    WHERE ds = MAX_PT('yj_new_dw.dws_pxb7_trade_order_item_summary_df')
    AND TO_CHAR(order_time,'yyyymmdd') BETWEEN '20260123' AND '20260129'
    AND game_name NOT IN ('bahei盒子')
    AND game_name NOT LIKE '%测试%'
    GROUP BY buyer_id
)
SELECT 
    COUNT(DISTINCT CASE WHEN 商品列表浏览 = 1 THEN u.merge_id END) AS 商品列表曝光人数,
    COUNT(DISTINCT CASE WHEN 商详页浏览 = 1 THEN u.merge_id END) AS 商详页浏览人数,
    COUNT(DISTINCT CASE WHEN 高意向点击 = 1 THEN u.merge_id END) AS 高意向点击人数,
    COUNT(DISTINCT CASE WHEN o.is_order = 1 THEN u.merge_id END) AS 下单人数,
    COUNT(DISTINCT CASE WHEN o.is_pay = 1 THEN u.merge_id END) AS 付款人数,
    COUNT(DISTINCT CASE WHEN o.is_complete = 1 THEN u.merge_id END) AS 完单人数,
    ROUND(COUNT(DISTINCT CASE WHEN 商详页浏览 = 1 THEN u.merge_id END) / NULLIF(COUNT(DISTINCT CASE WHEN 商品列表浏览 = 1 THEN u.merge_id END),0), 4) AS 商列到商详率,
    ROUND(COUNT(DISTINCT CASE WHEN 高意向点击 = 1 THEN u.merge_id END) / NULLIF(COUNT(DISTINCT CASE WHEN 商详页浏览 = 1 THEN u.merge_id END),0), 4) AS 商详到高意向率,
    ROUND(COUNT(DISTINCT CASE WHEN o.is_order = 1 THEN u.merge_id END) / NULLIF(COUNT(DISTINCT CASE WHEN 高意向点击 = 1 THEN u.merge_id END),0), 4) AS 高意向下单率,
    ROUND(COUNT(DISTINCT CASE WHEN o.is_pay = 1 THEN u.merge_id END) / NULLIF(COUNT(DISTINCT CASE WHEN o.is_order = 1 THEN u.merge_id END),0), 4) AS 下单付款率,
    ROUND(COUNT(DISTINCT CASE WHEN o.is_complete = 1 THEN u.merge_id END) / NULLIF(COUNT(DISTINCT CASE WHEN o.is_pay = 1 THEN u.merge_id END),0), 4) AS 支付完单率
FROM user_journey u
LEFT JOIN order_data o ON u.merge_id = o.buyer_id;

-- 金融业务分析 - 首付单明细
SELECT 
    TO_CHAR(a.create_time,'yyyymmdd') AS 首付时间,
    a.pre_audit_id AS 预审单单号,
    b.px_order_id AS px订单id,
    c.game_name AS 游戏名称,
    c.order_item_actual_pay_amount/100 AS px订单金额,
    c.payout_amount/100 AS px放款金额,
    e.loan_amount AS 借款金额,
    a.product_deposit_amount AS 商品首付金额,
    d.利息金额,
    a.indemnity_amount AS 包赔金额,
    a.service_fee_amount AS 手续费金额,
    a.trustee_fee_amount AS 托管费金额,
    a.valuation_fee_amount AS 估值服务费金额,
    a.total_deposit_amount AS 总首付金额
FROM (
    SELECT *
    FROM yj_new_dw.ods_jyp_finance_finance_order_deposit_df
    WHERE ds = MAX_PT('yj_new_dw.ods_jyp_finance_finance_order_deposit_df')
    AND TO_CHAR(create_time,'yyyymmdd') >= '20260123'
    AND TO_CHAR(create_time,'yyyymmdd') <= '20260129'
) a
LEFT JOIN (
    SELECT *
    FROM yj_new_dw.ods_jyp_finance_finance_order_pre_audit_df
    WHERE ds = MAX_PT('yj_new_dw.ods_jyp_finance_finance_order_pre_audit_df')
) b ON a.pre_audit_id = b.pre_audit_id
LEFT JOIN (
    SELECT order_item_id, order_item_actual_pay_amount, payout_amount, game_name
    FROM yj_new_dw.dwd_pxb7_trade_order_item_df
    WHERE ds = MAX_PT('yj_new_dw.dwd_pxb7_trade_order_item_df')
) c ON b.px_order_id = c.order_item_id
LEFT JOIN (
    SELECT pre_audit_id, SUM(need_interest_amount) + SUM(repay_interest_amount) AS 利息金额
    FROM yj_new_dw.ods_jyp_finance_finance_order_loan_plan_df
    WHERE ds = MAX_PT('yj_new_dw.ods_jyp_finance_finance_order_loan_plan_df')
    GROUP BY pre_audit_id
) d ON a.pre_audit_id = d.pre_audit_id
LEFT JOIN (
    SELECT pre_audit_id, loan_amount
    FROM yj_new_dw.ods_jyp_finance_finance_order_loan_df
    WHERE ds = MAX_PT('yj_new_dw.ods_jyp_finance_finance_order_loan_df')
) e ON a.pre_audit_id = e.pre_audit_id
WHERE b.order_status = 2
AND c.game_name NOT IN ('bahei盒子');

-- 商品分析 - 分月付商品在架情况
SELECT 
    game_name AS 游戏名称,
    COUNT(DISTINCT a.product_id) AS 在架商品数,
    COUNT(DISTINCT CASE WHEN b.product_id IS NOT NULL THEN a.product_id END) AS 分月付在架商品数,
    ROUND(COUNT(DISTINCT CASE WHEN b.product_id IS NOT NULL THEN a.product_id END) / NULLIF(COUNT(DISTINCT a.product_id),0), 4) AS 分月付在架商品数占比
FROM (
    SELECT *
    FROM yj_new_dw.dws_pxb7_product_info_df
    WHERE ds = MAX_PT('yj_new_dw.dws_pxb7_product_info_df')
    AND product_status_code = 1
    AND is_show = 1
) a
LEFT JOIN (
    SELECT product_id
    FROM yj_new_dw.ods_pxb7_product_product_promotion_price_snapshot_df
    WHERE ds = MAX_PT('yj_new_dw.ods_pxb7_product_product_promotion_price_snapshot_df')
    AND biz_type = 'finance'
    AND extend IS NOT NULL
    AND extend <> ''
) b ON a.product_id = b.product_id
WHERE game_name IN ('和平精英','火影忍者','王者荣耀','穿越火线-枪战王者','英雄联盟手游','金铲铲之战')
GROUP BY game_name;
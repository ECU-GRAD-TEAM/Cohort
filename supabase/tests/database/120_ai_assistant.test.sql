-- AI assistant (Dual-RAG + isolation addendum): JSON responses, audience/tenant isolation,
-- hybrid keyword + vector search with RRF, plus the forecasting tables it reports on.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

-- Deterministic embeddings: one-hot vectors, so cosine distances are 0 (same) or 1 (orthogonal)
create temp table onehot as
  select i, (select array_agg(case when g = i then 1 else 0 end order by g) from generate_series(1, 1024) g)::real[]::extensions.vector(1024) as v
    from generate_series(1, 5) as i;
grant select on onehot to market_backend;

-- Knowledge base fixtures (as the table owner)
insert into app.kb_documents (id, tenant_id, audience, doc_type, title, language, status) values
  ('bbbbbbbb-00e0-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'public', 'policy',   'Returns policy',      'en', 'published'),
  ('bbbbbbbb-00e0-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'public', 'policy',   'سياسة الاسترجاع',     'ar', 'published'),
  ('bbbbbbbb-00e0-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'admin',  'glossary', 'Metric glossary',     'en', 'published'),
  ('bbbbbbbb-00e0-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'public', 'policy',   'Old returns policy',  'en', 'superseded'),
  ('aaaaaaaa-00e0-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'public', 'policy',   'Returns policy',      'en', 'published');
insert into app.kb_chunks (id, tenant_id, document_id, audience, chunk_index, content, language, embedding) values
  ('bbbbbbbb-00e1-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e0-0000-0000-000000000001', 'public', 0,
   'Returns are accepted within 14 days with the receipt.', 'en', (select v from onehot where i = 1)),
  ('bbbbbbbb-00e1-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e0-0000-0000-000000000002', 'public', 0,
   'سياسة الاسترجاع خلال ١٤ يوم مع الإيصال', 'ar', (select v from onehot where i = 2)),
  ('bbbbbbbb-00e1-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e0-0000-0000-000000000003', 'admin', 0,
   'Net revenue means gross sales minus returns and discounts.', 'en', (select v from onehot where i = 3)),
  ('bbbbbbbb-00e1-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e0-0000-0000-000000000004', 'public', 0,
   'Returns are accepted within 30 days.', 'en', (select v from onehot where i = 1)),
  ('aaaaaaaa-00e1-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-00e0-0000-0000-000000000001', 'public', 0,
   'Returns are accepted within 14 days with the receipt.', 'en', (select v from onehot where i = 1));

set local role market_backend;

-- The owner asks the analytics assistant
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
insert into app.ai_conversations (id, tenant_id, audience, staff_id, title)
values ('bbbbbbbb-00e2-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'admin',
        'bbbbbbbb-0003-0000-0000-000000000001', 'Why did sales fall this week?');

select throws_ok(
  $$ insert into app.ai_messages (tenant_id, conversation_id, role, content)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e2-0000-0000-000000000001', 'assistant', 'Sales fell.') $$,
  '23514', null, 'an assistant reply must keep its structured JSON response');
select throws_ok(
  $$ insert into app.ai_messages (tenant_id, conversation_id, role, content, response)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e2-0000-0000-000000000001', 'assistant', 'x', '[]') $$,
  '23514', null, 'the response must be a JSON object');
select throws_ok(
  $$ insert into app.ai_messages (tenant_id, conversation_id, role, content, response)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e2-0000-0000-000000000001', 'assistant', 'x',
             '{"citations": []}') $$,
  '23514', null, 'the response must carry its answer text');
select throws_ok(
  $$ insert into app.ai_messages (tenant_id, conversation_id, role, content, response)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e2-0000-0000-000000000001', 'assistant', 'x',
             '{"answer": "x", "citations": "chunk-1"}') $$,
  '23514', null, 'citations, when present, are a list');
insert into app.ai_messages (tenant_id, conversation_id, role, content, response, pipeline, task_type, model,
                             temperature, top_p, prompt_tokens, completion_tokens, latency_ms, retrieval_confidence)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-00e2-0000-0000-000000000001', 'assistant',
        'Net revenue fell 12% week on week, mostly in Maadi.',
        '{"answer": "Net revenue fell 12% week on week, mostly in Maadi.",
          "citations": [{"chunk_id": "bbbbbbbb-00e1-0000-0000-000000000003", "quote": "Net revenue means gross sales minus returns and discounts."}],
          "sql": "select sales_date, net_revenue from analytics.sales_daily",
          "result": {"columns": ["sales_date", "net_revenue"], "rows": [["2026-10-04", 36900.00], ["2026-10-11", 32480.00]]},
          "chart": {"type": "line", "x": "sales_date", "series": ["net_revenue"]},
          "abstained": false}',
        'analytics', 'analysis', 'example-model', 0.20, 0.90, 1850, 210, 2300, 0.8700);
select is((select response -> 'chart' ->> 'type' from app.ai_messages
            where conversation_id = 'bbbbbbbb-00e2-0000-0000-000000000001'),
  'line', 'the full structured response round-trips, chart spec included');

-- Staff hybrid search reaches admin documents of their own tenant only
select is((select chunk_id from app.kb_hybrid_search('net revenue', (select v from onehot where i = 3), 5) limit 1),
  'bbbbbbbb-00e1-0000-0000-000000000003'::uuid, 'staff retrieve the admin metric glossary');
select is((select count(*)::int from app.kb_hybrid_search('returns within days', (select v from onehot where i = 1), 10)
            where chunk_id = 'bbbbbbbb-00e1-0000-0000-000000000004'),
  0, 'superseded policies are never retrieved');

-- Another staff member cannot read the owner's conversation
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000004');
select is((select count(*)::int from app.ai_conversations), 0, 'a conversation is private to whoever started it');
select is((select count(*)::int from app.ai_messages), 0, 'its messages are private too');

-- A shopper in the Nile storefront
select app.set_context(p_tenant_id   => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.kb_chunks where audience = 'admin'), 0, 'a shopper cannot read admin chunks');
select is((select count(*)::int from app.kb_documents where status <> 'published'), 0,
  'a shopper cannot read unpublished documents');
select throws_ok(
  $$ insert into app.ai_conversations (tenant_id, audience, staff_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'admin', 'bbbbbbbb-0003-0000-0000-000000000001') $$,
  '42501', null, 'a shopper cannot open an admin conversation');
select lives_ok(
  $$ insert into app.ai_conversations (tenant_id, audience, customer_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'shopper', 'cccccccc-0007-0000-0000-000000000001') $$,
  'a shopper can open a shopper conversation');

select is((select chunk_id from app.kb_hybrid_search('returns receipt', (select v from onehot where i = 1), 5) limit 1),
  'bbbbbbbb-00e1-0000-0000-000000000001'::uuid, 'the best keyword and vector match ranks first');
select is((select count(*)::int from app.kb_hybrid_search('returns receipt', (select v from onehot where i = 1), 10)
            where chunk_id in ('aaaaaaaa-00e1-0000-0000-000000000001', 'bbbbbbbb-00e1-0000-0000-000000000003',
                               'bbbbbbbb-00e1-0000-0000-000000000004')),
  0, 'an identical Alpha chunk, admin chunks and superseded chunks never reach a Nile shopper');
select is((select count(*)::int from app.kb_hybrid_search('net revenue', (select v from onehot where i = 3), 10, 'admin')),
  0, 'asking for the admin audience does not widen a shopper''s reach');
select is((select chunk_id from app.kb_hybrid_search('الاسترجاع', (select v from onehot where i = 5), 5) limit 1),
  'bbbbbbbb-00e1-0000-0000-000000000002'::uuid, 'an Arabic keyword query finds the Arabic policy');

-- Alpha staff get Alpha's chunk for the very same text and vector
select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select results_eq(
  $$ select chunk_id from app.kb_hybrid_search('returns receipt', (select v from onehot where i = 1), 10) $$,
  $$ values ('aaaaaaaa-00e1-0000-0000-000000000001'::uuid) $$,
  'each tenant retrieves only its own chunks');

-- Forecasts the assistant can report on
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000', p_system_actor => 'forecast_job');
select throws_ok(
  $$ insert into app.demand_forecasts (tenant_id, branch_id, product_id, model_version, generated_at, forecast_date,
                                       point_forecast, q10, q50, q90)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0005-0000-0000-000000000001', 'lgbm-tweedie-1', now(), '2026-10-12', 14, 16, 14, 20) $$,
  '23514', null, 'forecast quantiles must be ordered');
select lives_ok(
  $$ insert into app.reorder_points (tenant_id, branch_id, product_id, lead_time_days, safety_stock, reorder_point)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0005-0000-0000-000000000001', 3, 27.92, 132.92) $$,
  'a forecasting job can store a dynamic reorder point');

select * from finish();
rollback;

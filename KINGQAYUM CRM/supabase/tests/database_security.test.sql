-- Run with: supabase test db
-- All fixtures and role changes are inside the test transaction; pgTAP rolls
-- this file back after it finishes.
create extension if not exists pgtap with schema extensions;
select plan(43);
select ok(
 not has_table_privilege('anon','public.workspaces','SELECT')
 and not has_table_privilege('anon','public.workspace_memberships','SELECT')
 and not has_table_privilege('anon','public.prospects','SELECT')
 and not has_table_privilege('anon','public.interactions','SELECT')
 and not has_table_privilege('anon','public.followups','SELECT')
 and not has_table_privilege('anon','public.message_templates','SELECT')
 and not has_table_privilege('anon','public.clients','SELECT')
 and not has_table_privilege('anon','public.orders','SELECT')
 and not has_table_privilege('anon','public.payments','SELECT')
 and not has_table_privilege('anon','public.workspace_settings','SELECT'),
 'anonymous role has no direct SELECT privilege on workspace data'
);

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001','authenticated','authenticated','owner-a@test.invalid','',now(),'{}','{}',now(),now()),
  ('10000000-0000-4000-8000-000000000002','authenticated','authenticated','member-a@test.invalid','',now(),'{}','{}',now(),now()),
  ('10000000-0000-4000-8000-000000000003','authenticated','authenticated','owner-b@test.invalid','',now(),'{}','{}',now(),now()),
  ('10000000-0000-4000-8000-000000000004','authenticated','authenticated','outsider@test.invalid','',now(),'{}','{}',now(),now());

insert into public.workspaces(id,name,owner_user_id) values
 ('20000000-0000-4000-8000-000000000001','Workspace A','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000002','Workspace B','10000000-0000-4000-8000-000000000003');
insert into public.workspace_memberships(workspace_id,user_id,role) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','owner'),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','member'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003','owner');
insert into public.workspace_settings(workspace_id) values
 ('20000000-0000-4000-8000-000000000001'),('20000000-0000-4000-8000-000000000002');
insert into public.prospects(workspace_id,id,name) values
 ('20000000-0000-4000-8000-000000000001','prospect-a','Prospect A'),
 ('20000000-0000-4000-8000-000000000002','prospect-b','Prospect B');
insert into public.interactions(workspace_id,id,prospect_id,date,type) values
 ('20000000-0000-4000-8000-000000000001','interaction-a','prospect-a',current_date,'Other'),
 ('20000000-0000-4000-8000-000000000002','interaction-b','prospect-b',current_date,'Other');
insert into public.followups(workspace_id,id,prospect_id,due_date) values
 ('20000000-0000-4000-8000-000000000001','followup-a','prospect-a',current_date),
 ('20000000-0000-4000-8000-000000000002','followup-b','prospect-b',current_date);
insert into public.message_templates(workspace_id,id,name,body) values
 ('20000000-0000-4000-8000-000000000001','template-a','Template A','A'),
 ('20000000-0000-4000-8000-000000000002','template-b','Template B','B');
insert into public.clients(workspace_id,id,prospect_id,name) values
 ('20000000-0000-4000-8000-000000000001','client-a','prospect-a','Client A'),
 ('20000000-0000-4000-8000-000000000002','client-b','prospect-b','Client B');
insert into public.orders(workspace_id,id,client_id,title,price,status) values
 ('20000000-0000-4000-8000-000000000001','order-a','client-a','Order A',100,'pending'),
 ('20000000-0000-4000-8000-000000000002','order-b','client-b','Order B',100,'pending');

-- Membership can see its workspace and its workspace's rows across every
-- business table. The fixture contains one row per table/workspace.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select is((select count(*)::int from public.workspaces where id='20000000-0000-4000-8000-000000000001'),1,'member sees own workspace');
select is((select count(*)::int from public.workspace_memberships where workspace_id='20000000-0000-4000-8000-000000000001'),2,'member sees own workspace membership list');
select is((select count(*)::int from public.workspace_settings where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads workspace settings');
select is((select count(*)::int from public.prospects where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads prospects');
select is((with changed as (update public.prospects set name='Member edit' where workspace_id='20000000-0000-4000-8000-000000000001' and id='prospect-a' returning 1) select count(*)::int from changed),1,'member can update own workspace prospect');
select throws_ok($$update public.prospects set id='changed-id' where workspace_id='20000000-0000-4000-8000-000000000001' and id='prospect-a'$$,'22023',null,'record ID cannot be changed');
select is((select count(*)::int from public.interactions where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads interactions');
select is((select count(*)::int from public.followups where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads follow-ups');
select is((select count(*)::int from public.message_templates where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads templates');
select is((select count(*)::int from public.clients where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads clients');
select is((select count(*)::int from public.orders where workspace_id='20000000-0000-4000-8000-000000000001'),1,'member reads orders');
select is((select count(*)::int from public.payments where workspace_id='20000000-0000-4000-8000-000000000001'),0,'member reads payment rows (none exist yet)');
select throws_ok($$insert into public.workspace_settings(workspace_id) values ('20000000-0000-4000-8000-000000000001')$$,'42501',null,'ordinary member cannot write settings');
select throws_ok($$insert into public.payments(workspace_id,id,order_id,amount,date) values ('20000000-0000-4000-8000-000000000001','direct-pay','order-a',1,current_date)$$,'42501',null,'direct payment writes are denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select is((with changed as (update public.workspace_settings set business='Owner edit' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),1,'workspace owner can update settings');
reset role;

-- Authenticated non-member must neither observe nor alter Workspace A rows.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select is((select count(*)::int from public.workspaces where id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read workspace');
select is((select count(*)::int from public.workspace_memberships where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read memberships');
select is((select count(*)::int from public.workspace_settings where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read settings');
select is((select count(*)::int from public.prospects where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read prospects');
select is((select count(*)::int from public.interactions where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read interactions');
select is((select count(*)::int from public.followups where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read follow-ups');
select is((select count(*)::int from public.message_templates where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read templates');
select is((select count(*)::int from public.clients where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read clients');
select is((select count(*)::int from public.orders where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read orders');
select is((select count(*)::int from public.payments where workspace_id='20000000-0000-4000-8000-000000000001'),0,'non-member cannot read payments');
select is((with changed as (update public.prospects set name='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update a prospect');
select is((with changed as (update public.interactions set summary='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update interactions');
select is((with changed as (update public.followups set reason='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update follow-ups');
select is((with changed as (update public.message_templates set body='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update templates');
select is((with changed as (update public.clients set name='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update clients');
select is((with changed as (update public.orders set title='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update orders');
select is((with changed as (update public.workspace_settings set business='tampered' where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'non-member cannot update settings');
select is((with removed as (delete from public.orders where workspace_id='20000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from removed),0,'non-member cannot delete an order');
select throws_ok($$insert into public.prospects(workspace_id,id,name) values ('20000000-0000-4000-8000-000000000001','outsider-write','No')$$,'42501',null,'non-member cannot insert a prospect');
select throws_ok($$update public.payments set note='tampered' where workspace_id='20000000-0000-4000-8000-000000000001'$$,'42501',null,'payment updates are unavailable to browser roles');
select throws_ok($$select * from public.record_payment('20000000-0000-4000-8000-000000000001','unauthorized-pay','order-a',1,current_date,null,null)$$,'42501',null,'non-member cannot call payment RPC');
reset role;

-- Payment function uses the user's membership even though it runs as definer.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select is((select count(*)::int from public.record_payment('20000000-0000-4000-8000-000000000001','pay-a','order-a',60,current_date,'Cash','first')),1,'member records payment');
select is((select count(*)::int from public.record_payment('20000000-0000-4000-8000-000000000001','pay-a','order-a',60,current_date,'Cash','first')),1,'identical retry returns existing payment');
select throws_ok($$select * from public.record_payment('20000000-0000-4000-8000-000000000001','pay-a','order-a',60,current_date,'Cash','different')$$,'23505',null,'reused payment ID with different details is rejected');
select throws_ok($$select * from public.record_payment('20000000-0000-4000-8000-000000000001','pay-b','order-a',50,current_date,'Cash','over balance')$$,'22023',null,'payment cannot exceed locked order balance');
update public.orders set status='cancelled' where workspace_id='20000000-0000-4000-8000-000000000001' and id='order-a';
select is((select count(*)::int from public.record_payment('20000000-0000-4000-8000-000000000001','pay-a','order-a',60,current_date,'Cash','first')),1,'retry remains idempotent after order status changes');
select is((select count(*)::int from public.payments where workspace_id='20000000-0000-4000-8000-000000000001' and id='pay-a'),1,'retry does not duplicate payment');
reset role;

select * from finish();
rollback;

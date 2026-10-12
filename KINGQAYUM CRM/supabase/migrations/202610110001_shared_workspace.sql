-- Shared KingQayum CRM workspace schema. Existing record IDs remain text.
begin;
create table public.workspaces (
 id uuid primary key default gen_random_uuid(), name text not null check (length(trim(name)) between 1 and 120),
 owner_user_id uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.workspace_memberships (
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('owner','admin','member')),
 invited_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(),
 primary key (workspace_id,user_id)
);
create index workspace_memberships_user_idx on public.workspace_memberships(user_id,workspace_id);

create function public.is_workspace_member(target_workspace uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.workspace_memberships m where m.workspace_id=target_workspace and m.user_id=(select auth.uid()));
$$;
create function public.workspace_role(target_workspace uuid) returns text
language sql stable security definer set search_path = '' as $$
 select m.role from public.workspace_memberships m where m.workspace_id=target_workspace and m.user_id=(select auth.uid()) limit 1;
$$;
revoke all on function public.is_workspace_member(uuid) from public;
revoke all on function public.workspace_role(uuid) from public;
grant execute on function public.is_workspace_member(uuid) to authenticated;
grant execute on function public.workspace_role(uuid) to authenticated;

create table public.prospects (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null,
 name text not null check(length(trim(name)) between 1 and 240), category text, contact_name text, phone text,
 facebook text, instagram text, website text,
 source text check(source is null or source in ('WhatsApp group','Facebook','Referral','Instagram','Walk-in','Other')),
 source_group text, identified_date date, first_contact_date date, description text, opportunity text, service text,
 estimate numeric(14,2) not null default 0 check(estimate >= 0), last_contact date, next_followup date,
 priority text check(priority is null or priority in ('Low','Medium','High')), notes text,
 status text not null default 'New prospect' check(status in ('New prospect','Qualified','Contacted','Awaiting reply','Interested','Follow-up due','Negotiating','Won / client','Not interested','Rejected','Lost','Future opportunity')),
 converted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id)
);
create index prospects_updated_idx on public.prospects(workspace_id,updated_at desc) where deleted_at is null;
create index prospects_status_idx on public.prospects(workspace_id,status) where deleted_at is null;
create index prospects_followup_idx on public.prospects(workspace_id,next_followup) where deleted_at is null;

create table public.interactions (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null, prospect_id text not null,
 date date not null, type text not null check(type in ('Initial message sent','Reply received','Follow-up sent','Call or conversation','Quote sent','Meeting','Order confirmed','Other')),
 summary text, next_action text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id), foreign key(workspace_id,prospect_id) references public.prospects(workspace_id,id) on delete cascade
);
create index interactions_prospect_date_idx on public.interactions(workspace_id,prospect_id,date);

create table public.followups (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null, prospect_id text not null,
 due_date date not null, reason text, action text, completed boolean not null default false, cancelled boolean not null default false, completed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id), foreign key(workspace_id,prospect_id) references public.prospects(workspace_id,id) on delete cascade,
 check(not (completed and cancelled))
);
create index followups_due_idx on public.followups(workspace_id,due_date) where deleted_at is null and not completed and not cancelled;

create table public.message_templates (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null,
 name text not null check(length(trim(name)) between 1 and 240), category text, body text not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id)
);
create table public.clients (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null, prospect_id text,
 name text not null check(length(trim(name)) between 1 and 240), contact_name text, phone text, email text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id),
 foreign key(workspace_id,prospect_id) references public.prospects(workspace_id,id) on delete set null (prospect_id),
 unique(workspace_id,prospect_id)
);

create table public.orders (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null, client_id text not null,
 title text not null check(length(trim(title)) between 1 and 240), category text, description text,
 price numeric(14,2) not null check(price >= 0), order_date date, deadline date,
 status text not null check(status in ('pending','in progress','awaiting client feedback','revision','completed','cancelled')),
 revisions integer not null default 0 check(revisions >= 0), delivery_notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id), foreign key(workspace_id,client_id) references public.clients(workspace_id,id) on delete restrict
);
create index orders_client_idx on public.orders(workspace_id,client_id,order_date desc);
create table public.payments (
 workspace_id uuid not null references public.workspaces(id) on delete cascade, id text not null, order_id text not null,
 amount numeric(14,2) not null check(amount > 0), date date not null, method text, note text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0), deleted_at timestamptz,
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null,
 primary key(workspace_id,id), foreign key(workspace_id,order_id) references public.orders(workspace_id,id) on delete restrict
);
create index payments_order_date_idx on public.payments(workspace_id,order_id,date);
create index payments_date_idx on public.payments(workspace_id,date desc) where deleted_at is null;
-- A client-generated payment ID is an idempotency key. Locking the order row
-- serializes concurrent deposits so two devices cannot spend the same balance.
create function public.record_payment(
 p_workspace_id uuid, p_id text, p_order_id text, p_amount numeric, p_date date, p_method text default null, p_note text default null
) returns setof public.payments language plpgsql security definer set search_path = '' as $$
declare
 order_price numeric(14,2);
 order_status text;
 existing public.payments%rowtype;
 paid_total numeric(14,2);
begin
 if not public.is_workspace_member(p_workspace_id) then raise exception 'workspace access denied' using errcode='42501'; end if;
 if p_id is null or length(trim(p_id))=0 or p_amount is null or p_amount<=0 or p_date is null then
  raise exception 'invalid payment details' using errcode='22023';
 end if;
 -- Serialize requests that reuse the same idempotency key, even if a client
 -- accidentally retries against a different order. The hash is only a lock
 -- key; the primary key remains the authoritative uniqueness constraint.
 perform pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(p_workspace_id::text || ':' || p_id, 0)
 );
 select p.* into existing from public.payments p
  where p.workspace_id=p_workspace_id and p.id=p_id;
 if found then
  if existing.order_id is distinct from p_order_id
     or existing.amount is distinct from p_amount
     or existing.date is distinct from p_date
     or existing.method is distinct from p_method
     or existing.note is distinct from p_note then
   raise exception 'idempotency key was already used for another payment' using errcode='23505';
  end if;
  return query select existing.*;
  return;
 end if;
 select o.price,o.status into order_price,order_status from public.orders o
  where o.workspace_id=p_workspace_id and o.id=p_order_id and o.deleted_at is null for update;
 if not found then raise exception 'order not found' using errcode='P0002'; end if;
 if order_status='cancelled' then raise exception 'cannot record payment on a cancelled order' using errcode='22023'; end if;
 select coalesce(sum(p.amount),0) into paid_total from public.payments p
  where p.workspace_id=p_workspace_id and p.order_id=p_order_id and p.deleted_at is null;
 if paid_total+p_amount>order_price then raise exception 'payment exceeds remaining order balance' using errcode='22023'; end if;
 insert into public.payments(workspace_id,id,order_id,amount,date,method,note)
  values(p_workspace_id,p_id,p_order_id,p_amount,p_date,p_method,p_note);
 return query select p.* from public.payments p where p.workspace_id=p_workspace_id and p.id=p_id;
end;
$$;
revoke all on function public.record_payment(uuid,text,text,numeric,date,text,text) from public;
grant execute on function public.record_payment(uuid,text,text,numeric,date,text,text) to authenticated;
create table public.workspace_settings (
 workspace_id uuid primary key references public.workspaces(id) on delete cascade,
 business text not null default 'KingQayumEditz', designer text not null default 'KingQayum',
 tagline text not null default 'Designs that speak loud.', currency text not null default 'NGN' check(currency='NGN'),
 followup_interval integer not null default 3 check(followup_interval between 1 and 365),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision bigint not null default 1 check(revision > 0)
);

create function public.touch_workspace_settings() returns trigger language plpgsql set search_path = '' as $$
begin
 if new.workspace_id is distinct from old.workspace_id then
  raise exception 'workspace identity cannot be changed' using errcode='22023';
 end if;
 new.updated_at := clock_timestamp(); new.revision := old.revision + 1; return new;
end;
$$;
create trigger workspace_settings_touch before update on public.workspace_settings
for each row execute function public.touch_workspace_settings();

create function public.touch_workspace_record() returns trigger language plpgsql set search_path = '' as $$
begin
 new.updated_at := clock_timestamp();
 if tg_op='UPDATE' then
  if new.workspace_id is distinct from old.workspace_id or new.id is distinct from old.id then
   raise exception 'record identity cannot be changed' using errcode='22023';
  end if;
  new.created_at:=old.created_at; new.created_by:=old.created_by; new.revision:=old.revision+1;
 else
  new.revision:=1; new.created_by := (select auth.uid());
 end if;
 new.updated_by := (select auth.uid());
 return new;
end;
$$;
do $$ declare t text; begin
 foreach t in array array['prospects','interactions','followups','message_templates','clients','orders','payments'] loop
  execute format('create trigger %I_touch before insert or update on public.%I for each row execute function public.touch_workspace_record()',t,t);
 end loop;
end $$;

alter table public.workspaces enable row level security;
alter table public.workspace_memberships enable row level security;
alter table public.prospects enable row level security;
alter table public.interactions enable row level security;
alter table public.followups enable row level security;
alter table public.message_templates enable row level security;
alter table public.clients enable row level security;
alter table public.orders enable row level security;
alter table public.payments enable row level security;
alter table public.workspace_settings enable row level security;
create policy workspace_member_read on public.workspaces for select to authenticated using(public.is_workspace_member(id));
create policy membership_member_read on public.workspace_memberships for select to authenticated using(public.is_workspace_member(workspace_id));
do $$ declare t text; begin
 foreach t in array array['prospects','interactions','followups','message_templates','clients','orders','payments'] loop
  execute format('create policy %I_member_access on public.%I for all to authenticated using(public.is_workspace_member(workspace_id)) with check(public.is_workspace_member(workspace_id))',t,t);
 end loop;
end $$;
create policy settings_member_read on public.workspace_settings for select to authenticated using(public.is_workspace_member(workspace_id));
create policy settings_admin_write on public.workspace_settings for all to authenticated
 using(public.workspace_role(workspace_id) in ('owner','admin')) with check(public.workspace_role(workspace_id) in ('owner','admin'));

-- Membership writes are intentionally absent from browser RLS policies.
-- Explicitly revoke anonymous access as defense in depth even if project-level
-- default privileges grant future public-schema tables to anon by default.
revoke all on public.workspaces,public.workspace_memberships,public.prospects,
 public.interactions,public.followups,public.message_templates,public.clients,
 public.orders,public.payments,public.workspace_settings from anon;
revoke all on public.workspace_memberships from anon,authenticated;
grant select on public.workspace_memberships,public.workspaces to authenticated;
grant select,insert,update,delete on public.prospects,public.interactions,public.followups,public.message_templates,public.clients,public.orders,public.payments to authenticated;
revoke insert,update,delete on public.payments from authenticated;
grant select on public.payments to authenticated;
grant select,insert,update,delete on public.workspace_settings to authenticated;
commit;

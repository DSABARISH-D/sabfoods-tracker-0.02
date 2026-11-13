begin;
create table public.profiles(id uuid primary key references auth.users on delete cascade,full_name text not null default '',phone text default '',role text not null default 'customer' check(role in ('customer','cashier','admin')),created_at timestamptz not null default now());
create function public.new_profile() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into profiles(id,full_name) values(new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),100));return new;end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();
create function public.my_role() returns text language sql stable security definer set search_path=public as $$select role from profiles where id=auth.uid()$$;
create table public.categories(id uuid primary key default gen_random_uuid(),name text unique not null check(length(name) between 1 and 60));
create table public.products(id uuid primary key default gen_random_uuid(),category_id uuid references categories on delete set null,name text not null check(length(name) between 1 and 150),description text default '',price numeric(10,2) not null check(price>0),image_url text default '' check(image_url='' or image_url like 'https://%'),is_available boolean not null default true,stock_quantity integer not null default 0 check(stock_quantity>=0),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.restaurant_settings(id integer primary key check(id=1),restaurant_name text not null default 'Sabarish Fast Food',address text default '',phone text default '',opening_time text default '',closing_time text default '');
insert into restaurant_settings(id) values(1);
create table public.orders(id uuid primary key default gen_random_uuid(),order_number bigint generated always as identity unique,customer_id uuid references profiles,cashier_id uuid references profiles,customer_name text not null,phone text not null,order_type text not null check(order_type in('takeaway','dine-in')),subtotal numeric(10,2) not null default 0,total_amount numeric(10,2) not null default 0 check(total_amount>=0),payment_method text not null check(payment_method in('online','cash')),payment_status text not null default 'pending' check(payment_status in('pending','paid','failed','refunded')),order_status text not null default 'pending' check(order_status in('pending','confirmed','preparing','ready','completed','cancelled')),notes text default '',request_id uuid unique not null,created_at timestamptz not null default now());
create index on orders(customer_id,created_at desc);
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references orders,product_id uuid not null references products,product_name text not null,unit_price numeric(10,2) not null,quantity integer not null check(quantity>0),item_total numeric(10,2) not null);
create index on order_items(order_id);
create table public.payments(id uuid primary key default gen_random_uuid(),order_id uuid unique not null references orders,razorpay_order_id text unique,razorpay_payment_id text unique,amount numeric(10,2) not null,payment_status text not null default 'pending',verified_at timestamptz,created_at timestamptz not null default now());
create table public.inventory_history(id bigint generated always as identity primary key,product_id uuid references products,old_quantity integer,new_quantity integer,actor_id uuid,created_at timestamptz default now());
create function public.inventory_audit() returns trigger language plpgsql security definer set search_path=public as $$begin new.updated_at=now();if new.stock_quantity is distinct from old.stock_quantity then insert into inventory_history(product_id,old_quantity,new_quantity,actor_id) values(new.id,old.stock_quantity,new.stock_quantity,auth.uid());end if;return new;end$$;
create trigger stock_audit before update on products for each row execute function inventory_audit();

alter table profiles enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table restaurant_settings enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table payments enable row level security;
alter table inventory_history enable row level security;
create policy profile_read on profiles for select to authenticated using(id=auth.uid() or my_role()='admin');
create policy category_read on categories for select using(true);
create policy category_admin on categories for all to authenticated using(my_role()='admin') with check(my_role()='admin');
create policy product_read on products for select using(is_available or my_role() in('admin','cashier'));
create policy product_admin on products for all to authenticated using(my_role()='admin') with check(my_role()='admin');
create policy settings_read on restaurant_settings for select using(true);
create policy settings_admin on restaurant_settings for update to authenticated using(my_role()='admin') with check(my_role()='admin');
create policy order_read on orders for select to authenticated using(customer_id=auth.uid() or my_role() in('admin','cashier'));
create policy item_read on order_items for select to authenticated using(exists(select 1 from orders where orders.id=order_id));
create policy payment_read on payments for select to authenticated using(exists(select 1 from orders where orders.id=order_id));
create policy inventory_read on inventory_history for select to authenticated using(my_role()='admin');
revoke all on profiles,categories,products,restaurant_settings,orders,order_items,payments,inventory_history from anon,authenticated;
grant select on categories,products,restaurant_settings to anon,authenticated;
grant select on profiles,orders,order_items,payments,inventory_history to authenticated;
grant insert,update,delete on categories,products to authenticated;
grant update on restaurant_settings to authenticated;

create function public.place_order(p_items jsonb,p_name text,p_phone text,p_type text,p_method text,p_notes text,p_request_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_product products%rowtype; v_item record; v_total numeric(10,2):=0; v_role text:=my_role(); v_existing orders%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 if p_request_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into v_existing from orders where request_id=p_request_id;
 if found then if v_existing.customer_id<>auth.uid() then raise exception 'Invalid request';end if;return v_existing.id;end if;
 if p_method not in('cash','online') or p_method is null or (p_method='cash' and v_role not in('admin','cashier')) then raise exception 'Payment method not allowed';end if;
 if p_type not in('takeaway','dine-in') or p_type is null then raise exception 'Invalid order type';end if;
 if coalesce(length(trim(p_name)),0) not between 1 and 100 or coalesce(length(p_phone),0) not between 7 and 20 or length(p_notes)>500 then raise exception 'Check customer details';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Bag must contain 1–50 items';end if;
 if exists(select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x->'id') is distinct from 'string' or jsonb_typeof(x->'quantity') is distinct from 'number' or (x->>'quantity') !~ '^[0-9]+$' or not (x ? 'id' and x ? 'quantity')) then raise exception 'Invalid items';end if;
 insert into orders(customer_id,cashier_id,customer_name,phone,order_type,payment_method,notes,request_id) values(auth.uid(),case when v_role in('admin','cashier') then auth.uid() end,trim(p_name),p_phone,p_type,p_method,p_notes,p_request_id) returning id into v_id;
 -- Group duplicates; lock stock in consistent UUID order to avoid deadlocks.
 for v_item in select (x->>'id')::uuid as id,sum((x->>'quantity')::integer)::integer as quantity from jsonb_array_elements(p_items) x group by 1 order by 1 loop
  if v_item.quantity not between 1 and 100 then raise exception 'Quantity must be between 1 and 100';end if;
  select * into v_product from products where id=v_item.id for update;
  if not found or not v_product.is_available or v_product.stock_quantity<v_item.quantity then raise exception 'An item is unavailable or has insufficient stock';end if;
  update products set stock_quantity=stock_quantity-v_item.quantity where id=v_item.id;
  insert into order_items(order_id,product_id,product_name,unit_price,quantity,item_total) values(v_id,v_product.id,v_product.name,v_product.price,v_item.quantity,v_product.price*v_item.quantity);
  v_total:=v_total+v_product.price*v_item.quantity;
 end loop;
 if v_total<=0 then raise exception 'Empty order';end if;
 update orders set subtotal=v_total,total_amount=v_total,payment_status=case when p_method='cash' then 'paid' else 'pending' end,order_status=case when p_method='cash' then 'confirmed' else 'pending' end where id=v_id;
 insert into payments(order_id,amount,payment_status,verified_at) values(v_id,v_total,case when p_method='cash' then 'paid' else 'pending' end,case when p_method='cash' then now() end);
 return v_id;
end $$;
create function public.advance_order(p_id uuid) returns void language plpgsql security definer set search_path=public as $$declare o orders%rowtype;begin
 if coalesce(my_role(),'') not in('admin','cashier') then raise exception 'Staff only';end if;
 select * into o from orders where id=p_id for update;
 if not found or o.payment_status<>'paid' or o.order_status not in('confirmed','preparing','ready') then raise exception 'Order cannot advance';end if;
 update orders set order_status=case o.order_status when 'confirmed' then 'preparing' when 'preparing' then 'ready' when 'ready' then 'completed' end where id=p_id;
end$$;
create function public.cancel_unpaid_order(p_id uuid) returns void language plpgsql security definer set search_path=public as $$declare o orders%rowtype;i record;begin
 if coalesce(my_role(),'') not in('admin','cashier') then raise exception 'Staff only';end if;
 select * into o from orders where id=p_id for update;
 if not found then raise exception 'Order not found';end if;
 if o.order_status='cancelled' then return;end if;
 if o.payment_status='paid' or o.order_status<>'pending' or exists(select 1 from payments where order_id=p_id and razorpay_order_id is not null) then raise exception 'Payment may be in progress. Reconcile in Razorpay before cancellation.';end if;
 for i in select product_id,quantity from order_items where order_id=p_id order by product_id loop update products set stock_quantity=stock_quantity+i.quantity where id=i.product_id;end loop;
 update orders set order_status='cancelled' where id=p_id;
end$$;
create function public.set_user_role(p_id uuid,p_role text) returns void language plpgsql security definer set search_path=public as $$begin
 if my_role() is distinct from 'admin' then raise exception 'Admin only';end if;
 if p_id=auth.uid() then raise exception 'Cannot change your own role';end if;
 if p_role not in('customer','cashier','admin') or p_role is null then raise exception 'Invalid role';end if;
 update profiles set role=p_role where id=p_id;
end$$;
-- Called only by Edge Functions using the service-role key.
create function public.attach_payment_order(p_id uuid,p_razorpay_id text) returns text language plpgsql security definer set search_path=public as $$declare o orders%rowtype;v_existing text;begin
 select * into o from orders where id=p_id for update;
 if not found or o.order_status<>'pending' or o.payment_method<>'online' then raise exception 'Order cannot accept a payment';end if;
 select razorpay_order_id into v_existing from payments where order_id=p_id for update;
 if v_existing is not null then return v_existing;end if;
 update payments set razorpay_order_id=p_razorpay_id where order_id=p_id;
 return p_razorpay_id;
end$$;
create function public.confirm_payment(p_razorpay_order text,p_payment text,p_amount integer) returns void language plpgsql security definer set search_path=public as $$declare v_id uuid;o orders%rowtype;p payments%rowtype;begin
 select order_id into v_id from payments where razorpay_order_id=p_razorpay_order;
 if not found then raise exception 'Payment order not found';end if;
 select * into o from orders where id=v_id for update;
 select * into p from payments where order_id=v_id for update;
 if o.payment_method<>'online' or round(o.total_amount*100)::integer<>p_amount then raise exception 'Payment amount mismatch';end if;
 if p.payment_status='paid' then if p.razorpay_payment_id<>p_payment then raise exception 'Conflicting payment';end if;return;end if;
 if o.order_status<>'pending' then raise exception 'Order not payable';end if;
 update payments set payment_status='paid',razorpay_payment_id=p_payment,verified_at=now() where order_id=v_id;
 update orders set payment_status='paid',order_status='confirmed' where id=v_id;
end$$;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.my_role() to anon,authenticated;
grant execute on function public.place_order(jsonb,text,text,text,text,text,uuid),public.advance_order(uuid),public.cancel_unpaid_order(uuid),public.set_user_role(uuid,text) to authenticated;
grant execute on function public.attach_payment_order(uuid,text),public.confirm_payment(text,text,integer) to service_role;
grant all on all tables in schema public to service_role;
grant usage,select on all sequences in schema public to service_role;
insert into categories(name) values('Rice'),('Noodles'),('Sides'),('Combos');
-- Real initial menu; stock starts at zero until the owner records available quantities.
insert into products(name,price,category_id,description) select v.name,v.price,c.id,v.description from (values
 ('Veg Fried Rice',50,'Rice','Vegetables tossed with rice.'),('Chicken Rice',90,'Rice','Freshly prepared chicken fried rice.'),('Chicken Rice Special',110,'Rice','Our special chicken rice.'),('Chicken Chilli',60,'Sides','Price per 100g portion.'),('Egg Rice',60,'Rice','Egg fried rice, made to order.'),('Veg Noodles',50,'Noodles','Vegetable stir-fried noodles.'),('Egg Noodles',60,'Noodles','Noodles tossed with egg.'),('Chicken Rice + Chicken Chilli Combo',150,'Combos','Chicken rice with a portion of chicken chilli.'),('Egg Rice + Chicken Chilli Combo',110,'Combos','Egg rice with a portion of chicken chilli.')) as v(name,price,category,description) join categories c on c.name=v.category;
commit;

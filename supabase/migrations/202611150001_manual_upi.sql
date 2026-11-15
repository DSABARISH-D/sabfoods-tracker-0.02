-- Manual UPI: customer claims are NOT settlement proof.
begin;
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check check(payment_method in ('online','cash','manual_upi'));
alter table public.restaurant_settings add column if not exists upi_qr_url text not null default '' check(upi_qr_url='' or upi_qr_url like 'https://%');
alter table public.payments add column if not exists upi_utr text;
alter table public.payments add column if not exists upi_claimed_at timestamptz;
alter table public.payments add column if not exists upi_reviewed_by uuid references public.profiles(id);
alter table public.payments add column if not exists upi_review_note text;
alter table public.payments add column if not exists upi_reviewed_at timestamptz;
create unique index if not exists payments_upi_utr_unique on public.payments(upi_utr) where upi_utr is not null;
create or replace function public.place_order(p_items jsonb,p_name text,p_phone text,p_type text,p_method text,p_notes text,p_request_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_product public.products%rowtype; v_item record; v_total numeric(10,2):=0; v_role text:=public.my_role(); v_existing public.orders%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 if p_request_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into v_existing from public.orders where request_id=p_request_id;
 if found then if v_existing.customer_id<>auth.uid() then raise exception 'Invalid request';end if;return v_existing.id;end if;
 if p_method not in('cash','online','manual_upi') or p_method is null or (p_method='cash' and v_role not in('admin','cashier')) then raise exception 'Payment method not allowed';end if;
 if p_type not in('takeaway','dine-in') or p_type is null then raise exception 'Invalid order type';end if;
 if coalesce(length(trim(p_name)),0) not between 1 and 100 or coalesce(length(p_phone),0) not between 7 and 20 or length(p_notes)>500 then raise exception 'Check customer details';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Bag must contain 1–50 items';end if;
 if exists(select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x->'id') is distinct from 'string' or jsonb_typeof(x->'quantity') is distinct from 'number' or (x->>'quantity') !~ '^[0-9]+$' or not (x ? 'id' and x ? 'quantity')) then raise exception 'Invalid items';end if;
 insert into public.orders(customer_id,cashier_id,customer_name,phone,order_type,payment_method,notes,request_id) values(auth.uid(),case when v_role in('admin','cashier') then auth.uid() end,trim(p_name),p_phone,p_type,p_method,p_notes,p_request_id) returning id into v_id;
 for v_item in select (x->>'id')::uuid as id,sum((x->>'quantity')::integer)::integer as quantity from jsonb_array_elements(p_items) x group by 1 order by 1 loop
  if v_item.quantity not between 1 and 100 then raise exception 'Quantity must be between 1 and 100';end if;
  select * into v_product from public.products where id=v_item.id for update;
  if not found or not v_product.is_available or v_product.stock_quantity<v_item.quantity then raise exception 'An item is unavailable or has insufficient stock';end if;
  update public.products set stock_quantity=stock_quantity-v_item.quantity where id=v_item.id;
  insert into public.order_items(order_id,product_id,product_name,unit_price,quantity,item_total) values(v_id,v_product.id,v_product.name,v_product.price,v_item.quantity,v_product.price*v_item.quantity);
  v_total:=v_total+v_product.price*v_item.quantity;
 end loop;
 if v_total<=0 then raise exception 'Empty order';end if;
 update public.orders set subtotal=v_total,total_amount=v_total,payment_status=case when p_method='cash' then 'paid' else 'pending' end,order_status=case when p_method='cash' then 'confirmed' else 'pending' end where id=v_id;
 insert into public.payments(order_id,amount,payment_status,verified_at) values(v_id,v_total,case when p_method='cash' then 'paid' else 'pending' end,case when p_method='cash' then now() end);
 return v_id;
end $$;
create function public.submit_upi_utr(p_order uuid,p_utr text) returns void language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_utr is null or p_utr !~ '^[0-9]{12,22}$' then raise exception 'Enter a valid numeric UPI transaction reference';end if;
 select * into o from public.orders where id=p_order for update;
 if not found or o.customer_id<>auth.uid() or o.payment_method<>'manual_upi' or o.payment_status<>'pending' or o.order_status<>'pending' then raise exception 'Order cannot accept a UPI claim';end if;
 if exists(select 1 from public.payments where upi_utr=p_utr and order_id<>p_order) then raise exception 'Reference already submitted';end if;
 update public.payments set upi_utr=p_utr,upi_claimed_at=now(),upi_reviewed_by=null,upi_review_note=null,upi_reviewed_at=null where order_id=p_order and payment_status='pending';
 if not found then raise exception 'Payment claim unavailable';end if;
end $$;
create function public.review_upi_payment(p_order uuid,p_approve boolean,p_note text) returns void language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype; p public.payments%rowtype;
begin
 if public.my_role() is distinct from 'admin' then raise exception 'Admin only';end if;
 if p_approve is null or length(trim(coalesce(p_note,''))) not between 5 and 500 then raise exception 'Bank verification evidence or rejection reason required (5-500 characters)';end if;
 select * into o from public.orders where id=p_order for update;
 select * into p from public.payments where order_id=p_order for update;
 if o.payment_method<>'manual_upi' or o.payment_status<>'pending' or o.order_status<>'pending' or p.upi_utr is null or p.payment_status<>'pending' then raise exception 'UPI payment not reviewable';end if;
 update public.payments set payment_status=case when p_approve then 'paid' else 'rejected' end,verified_at=case when p_approve then now() else null end,upi_reviewed_by=auth.uid(),upi_review_note=trim(p_note),upi_reviewed_at=now() where order_id=p_order;
 update public.orders set payment_status=case when p_approve then 'paid' else 'failed' end,order_status=case when p_approve then 'confirmed' else 'pending' end where id=p_order;
end $$;
-- Do not allow a manual UPI order to be cancelled while a claim is awaiting review.
create or replace function public.cancel_unpaid_order(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype;i record;begin
 if coalesce(public.my_role(),'') not in('admin','cashier') then raise exception 'Staff only';end if;
 select * into o from public.orders where id=p_id for update;
 if not found then raise exception 'Order not found';end if;
 if o.order_status='cancelled' then return;end if;
 if o.payment_status='paid' or o.order_status<>'pending' or exists(select 1 from public.payments where order_id=p_id and (razorpay_order_id is not null or upi_utr is not null)) then raise exception 'Payment may be in progress. Reconcile before cancellation.';end if;
 for i in select product_id,quantity from public.order_items where order_id=p_id order by product_id loop update public.products set stock_quantity=stock_quantity+i.quantity where id=i.product_id;end loop;
 update public.orders set order_status='cancelled' where id=p_id;
end$$;
revoke execute on function public.submit_upi_utr(uuid,text),public.review_upi_payment(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.submit_upi_utr(uuid,text),public.review_upi_payment(uuid,boolean,text) to authenticated;
commit;

import {admin,endpoint,owner,razor} from '../_shared/payment.ts';
endpoint(async req=>{const {order_id}=await req.json();const order=await owner(req,order_id);if(order.payment_status==='paid')return {paid:true};if(order.order_status!=='pending'||order.payment_method!=='online')throw new Error('Order cannot be paid');let razorId=order.payments[0]?.razorpay_order_id;
 if(!razorId){const created=await razor('orders',{amount:Math.round(Number(order.total_amount)*100),currency:'INR',receipt:order.id,notes:{order_id:order.id}});const {data,error}=await admin.rpc('attach_payment_order',{p_id:order.id,p_razorpay_id:created.id});if(error)throw error;razorId=data;}
 return {razorpay_order_id:razorId,key_id:Deno.env.get('RAZORPAY_KEY_ID'),amount:Math.round(Number(order.total_amount)*100)};
});

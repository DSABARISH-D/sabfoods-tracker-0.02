import {createClient} from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const db = url && key ? createClient(url,key) : null;
export const money = n => new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:2}).format(Number(n || 0));
export async function unwrap(query){const {data,error}=await query;if(error)throw error;return data;}
export async function invoke(name,body){const {data,error}=await db.functions.invoke(name,{body});if(error){let detail;try{detail=await error.context?.json();}catch{}throw new Error(detail?.error||error.message);}return data;}
export async function pay(order){
 const payment=await invoke('create-payment',{order_id:order.id});
 if(payment.paid)return;
 if(!window.Razorpay)await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://checkout.razorpay.com/v1/checkout.js';s.onload=resolve;s.onerror=()=>{s.remove();reject(new Error('Unable to load payment checkout. Check your connection.'));};document.head.appendChild(s);});
 return new Promise((resolve,reject)=>{const checkout=new window.Razorpay({key:payment.key_id,order_id:payment.razorpay_order_id,amount:payment.amount,currency:'INR',name:'Sabarish Fast Food',prefill:{name:order.customer_name,contact:order.phone},theme:{color:'#e85420'},handler:async result=>{try{await invoke('verify-payment',{order_id:order.id,...result});resolve();}catch(e){reject(e);}},modal:{ondismiss:()=>reject(new Error('Checkout closed. Your order remains pending; retry from Orders.'))}});checkout.on('payment.failed',()=>reject(new Error('Payment failed. Retry from Orders; payment has not been confirmed.')));checkout.open();});
}

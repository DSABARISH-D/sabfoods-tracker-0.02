import {endpoint,owner,razor,validHmac,confirm} from '../_shared/payment.ts';
endpoint(async req=>{const body=await req.json();const order=await owner(req,body.order_id);const razorId=order.payments[0]?.razorpay_order_id;
 if(!razorId||razorId!==body.razorpay_order_id||!/^pay_[A-Za-z0-9]+$/.test(body.razorpay_payment_id||''))throw new Error('Invalid payment details');
 if(!await validHmac(`${razorId}|${body.razorpay_payment_id}`,body.razorpay_signature,Deno.env.get('RAZORPAY_KEY_SECRET')!))throw new Error('Invalid payment signature');
 const payment=await razor(`payments/${body.razorpay_payment_id}`);if(payment.order_id!==razorId)throw new Error('Payment order mismatch');await confirm(payment);return {verified:true};
});

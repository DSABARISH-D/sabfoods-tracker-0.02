import {test} from 'node:test';
import assert from 'node:assert/strict';
import {cartTotal,changeQuantity} from '../src/cart.js';
test('money sums in paise without floating-point drift',()=>{assert.equal(cartTotal([{id:'a',quantity:3},{id:'b',quantity:1}],[{id:'a',price:'0.10'},{id:'b',price:'0.20'}]),0.5);});
test('quantity cannot exceed stock or fall below zero',()=>{let c=changeQuantity([],'a',1,2);c=changeQuantity(c,'a',5,2);assert.deepEqual(c,[{id:'a',quantity:2}]);assert.deepEqual(changeQuantity(c,'a',-3,2),[]);assert.deepEqual(changeQuantity([],'a',1,0),[]);});

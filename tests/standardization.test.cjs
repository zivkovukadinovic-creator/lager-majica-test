const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '../lager-majica-test-2.html'), 'utf8');
const script = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].at(-1)[1];
function app() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {value:'',textContent:'',innerHTML:'',disabled:false,
      listeners:{},options:[],classList:{add(){},remove(){}},reset(){},
      addEventListener(name, fn){this.listeners[name]=fn;},
      replaceChildren(option){this.options=[option];}, add(option){this.options.push(option);}});
    return elements.get(id);
  };
  const context = vm.createContext({document:{getElementById:element},window:{},
    Option:function(text,value){this.text=text;this.value=value;},console});
  vm.runInContext(script, context);
  return {run:code=>vm.runInContext(code,context), element, context};
}
test('models: all requested aliases, decomposed accents, spaces; custom names preserved',()=>{
  const a=app();
  for(const s of ['Muska','Muška','muska','MUŠKA','  Muš ka  ','Mus\u030cka']) assert.equal(a.run(`normalizeModel(${JSON.stringify(s)})`),'Muška');
  for(const s of ['Zenska','Ženska','zenska','ŽENSKA']) assert.equal(a.run(`normalizeModel(${JSON.stringify(s)})`),'Ženska');
  for(const s of ['Djecja','Dječja','Djecija','Dječija','djecja','DJECJA']) assert.equal(a.run(`normalizeModel(${JSON.stringify(s)})`),'Dječija');
  assert.equal(a.run('normalizeModel("Basic Premium")'),'Basic Premium');
});
test('sizes: aliases, large sizes, natural order and unknown labels',()=>{
  const a=app();
  for(const [raw,expected] of [['xs','XS'],['s','S'],['m','M'],['l','L'],['xl','XL'],['XXL','2XL'],['xxxL','3XL'],['XXXXL','4XL'],['XXXXXL','5XL'],['XXXXXXL','6XL'],['7xl','7XL'],['XXXXXXXXL','8XL'],['128','128']]) assert.equal(a.run(`normalizeSize(${JSON.stringify(raw)})`),expected);
  assert.equal(a.run('JSON.stringify(["10XL","3XL","XS","XL","2XL","S","M","L","6XL"].sort(compareSizes))'),JSON.stringify(['XS','S','M','L','XL','2XL','3XL','6XL','10XL']));
});
test('loaded rows retain IDs, quantities and minima; filters collapse aliases; all filters combine',async()=>{
  const a=app();
  a.run(`currentUser={id:'fake'}; db={from(){return {select(){return {order:async()=>({data:[
    {id:1,model:'Muska',boja:'crna',velicina:'XXL',kolicina:3,minimalna_kolicina:4},
    {id:2,model:'Muška',boja:'crna',velicina:'2xl',kolicina:7,minimalna_kolicina:2},
    {id:3,model:'Zenska',boja:'bijela',velicina:'xs',kolicina:1,minimalna_kolicina:2}
  ]})}}}}}`);
  await a.run('loadShirts()');
  assert.equal(a.run('shirts.length'),3);
  assert.equal(a.run('shirts.find(x=>x.id===1).kolicina'),3);
  assert.equal(a.run('shirts.find(x=>x.id===2).minimalna_kolicina'),2);
  assert.deepEqual(a.element('filterVelicina').options.map(x=>x.value),['','XS','2XL']);
  a.element('filterModel').value='Muška'; a.element('filterBoja').value='crna'; a.element('filterVelicina').value='2XL';
  a.run('renderShirts()'); assert.match(a.element('shirtList').innerHTML,/Muška/); assert.doesNotMatch(a.element('shirtList').innerHTML,/Ženska/);
  assert.match(a.element('dopunaList').innerHTML,/XS/);
});
async function save({rows=[],edit=null}) {
  const a=app(); const calls=[];
  a.context.rows=rows; a.context.calls=calls;
  a.run(`currentUser={id:'fake'};isEditor=true;editingId=${JSON.stringify(edit)};
    db={from(){return {select(){return {data:rows}},update(payload){calls.push(['update',payload]); return {eq(){return {select(){return {data:[{id:1}]}}}}}}}},
    rpc:async(name,payload)=>{calls.push(['rpc',name,payload]);return {data:1}}};
    loadShirts=async()=>{};`);
  for(const [id,value] of Object.entries({model:'Muska',boja:'crna',velicina:'xxl',kolicina:'3',minimalna_kolicina:'5'})) a.element(id).value=value;
  await a.element('shirtForm').listeners.submit({preventDefault(){}});
  return {a,calls};
}
test('new write sends canonical RPC payload; legacy single match reuses stored key',async()=>{
  const {calls}=await save({});
  assert.equal(calls[0][2].p_model,'Muška'); assert.equal(calls[0][2].p_velicina,'2XL');
  const existing=await save({rows:[{id:9,model:'Muska',boja:'crna',velicina:'XXL'}]});
  assert.equal(existing.calls[0][2].p_model,'Muska'); assert.equal(existing.calls[0][2].p_velicina,'XXL');
  assert.equal(existing.calls[0][2].p_kolicina,3); assert.equal(existing.calls[0][2].p_minimalna_kolicina,5);
});
test('existing duplicate groups and edit collisions block writes without merging',async()=>{
  const rows=[{id:1,model:'Muska',boja:'crna',velicina:'XXL'},{id:2,model:'Muška',boja:'crna',velicina:'2XL'}];
  const duplicate=await save({rows}); assert.equal(duplicate.calls.length,0); assert.match(duplicate.a.element('status').textContent,/provjera/);
  const collision=await save({rows:rows.slice(0,1),edit:2}); assert.equal(collision.calls.length,0); assert.match(collision.a.element('status').textContent,/već postoji/);
  const own=await save({rows:rows.slice(0,1),edit:1}); assert.equal(own.calls[0][0],'update'); assert.equal(own.calls[0][1].velicina,'2XL');
});
test('Excel receives canonical labels and natural order without altering quantities/minima',async()=>{
  const a=app(), rows=[];
  const row=()=>({getCell(){return {};}});
  a.context.ExcelJS={Workbook:class {
    constructor(){this.xlsx={writeBuffer:async()=>new Uint8Array()};}
    addWorksheet(){return {mergeCells(){},getCell(){return {};},getRow:row,
      addRow(values){rows.push(values);return row();},rowCount:8};}
  }};
  a.context.window.ExcelJS=a.context.ExcelJS;
  a.context.Blob=class {};
  a.context.URL={createObjectURL(){return 'blob:mock';},revokeObjectURL(){}};
  a.context.setTimeout=()=>{};
  a.context.document.createElement=()=>({click(){},remove(){}});
  a.context.document.body={append(){}};
  a.run(`shirts=['XXL','xs','10xl','XL'].map((velicina,id)=>normalizeShirt({id,model:'Djecja',boja:'crna',velicina,kolicina:1,minimalna_kolicina:3}));`);
  await a.run('exportOrder()');
  assert.deepEqual(rows.map(r=>r[2]),['XS','XL','2XL','10XL']);
  assert.ok(rows.every(r=>r[0]==='Dječija' && r[3]===1 && r[4]===3));
  assert.match(a.element('status').textContent,/preuzet/);
});

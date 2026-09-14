const fs = require('fs/promises');
const sharp = require('C:/Users/mali7/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const path = require('path');
const root = 'C:/1000 Hidden Objects/output';
const ui = root + '/game-art/additions/ui', hub = root + '/creator-hub';
const gen = 'C:/Users/mali7/.codex/generated_images/01a099f7-404e-7610-a1a8-f0373b16d0b1/';
const ink = '#302B46';
const group = body => `<g stroke="${ink}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round">${body}</g>`;
const svg = (body,w=256,h=w,v=`0 0 ${w} ${h}`)=>`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${v}">${body}</svg>`;
const star = (x,y,r,fill='#FFC83E') => {let p=[];for(let i=0;i<10;i++){let a=-Math.PI/2+i*Math.PI/5,s=i%2?r*.46:r;p.push(`${x+Math.cos(a)*s},${y+Math.sin(a)*s}`)}return `<polygon points="${p.join(' ')}" fill="${fill}"/>`};
const text = (s,x,y,size,fill='white')=>`<text x="${x}" y="${y}" text-anchor="middle" font-family="Arial Black,DejaVu Sans" font-weight="900" font-size="${size}" fill="${fill}" stroke="${ink}" stroke-width="${fill===ink?0:6}" paint-order="stroke" stroke-linejoin="round">${s}</text>`;
const clock = group('<path d="M184 144v-12h22v12 M214 153l10-9" fill="#52BAEF"/><circle cx="195" cy="183" r="37" fill="#FFF9E5"/><path d="M195 160v23l16 10" fill="none"/>');
const badge2x = group('<rect x="15" y="16" width="91" height="59" rx="19" fill="#FFC83E"/>')+text('2X',60,59,38,ink);
async function save(dir,name,body,w=256,h=w,view){const s=svg(body,w,h,view);await fs.writeFile(`${dir}/${name}.svg`,s);await sharp(Buffer.from(s)).png().toFile(`${dir}/${name}.png`);return s;}
async function main(){
await fs.mkdir(ui,{recursive:true});await fs.mkdir(hub,{recursive:true});
const base={};for(const k of ['Icon_Strength','Icon_Cash','Icon_Hint','Icon_Key'])base[k]=(await fs.readFile(root+'/game-art/ui/'+k+'.svg','utf8')).replace(/^<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'');
const products={};
products.DoubleCash=`<g transform="translate(-10,-21) scale(.87)">${base.Icon_Cash}</g><g transform="translate(25,45) scale(.87)">${base.Icon_Cash}</g>`+badge2x;
products.StrongerHands=`<g transform="translate(-5,14) scale(.94)">${base.Icon_Strength}</g>`+group('<circle cx="195" cy="60" r="40" fill="#60D6A1"/><path d="M175 60h40 M195 40v40" stroke="white" stroke-width="12"/>');
const glove=group('<path d="M99 189L83 132Q68 108 84 96Q96 89 110 110V53Q110 34 125 37Q136 38 136 54V92V36Q136 17 151 22Q162 24 162 41V92V47Q164 28 178 34Q190 39 188 56V101V67Q191 49 203 57Q216 60 212 79L207 153Q206 178 184 193L182 215H108Z" fill="#FFF4DD"/><path d="M107 197h78v27h-78Z" fill="#52BAEF"/>');
products.FastHands=group('<path d="M17 91h63 M5 129h59 M24 169h52" fill="none" stroke="#52BAEF" stroke-width="13"/>')+glove;
products.ThrowBoost=group('<path d="M26 197Q65 67 172 57Q109 102 116 176Q85 146 26 197Z" fill="#FFC83E"/><path d="M28 166Q49 99 101 72 M47 208l22-30" fill="none" stroke="#FF8D58"/><circle cx="158" cy="105" r="57" fill="#FF9456"/><path d="M106 84l99 42 M139 52q-9 51 31 109 M188 58q-50 7-59 94" fill="none"/><path d="M195 224v-45h-23l37-39l35 39h-23v45Z" fill="#60D6A1"/>');
products.VIP=group('<path d="M36 84l46 36l46-69l46 69l46-36l-21 113H57Z" fill="#FFC83E"/><path d="M55 173h146v35H55Z" fill="#F1A529"/><circle cx="35" cy="76" r="13" fill="#FFF0AE"/><circle cx="128" cy="43" r="13" fill="#FFF0AE"/><circle cx="221" cy="76" r="13" fill="#FFF0AE"/>')+text('VIP',128,162,47,ink);
products.Strength10Min=`<g transform="translate(-3,34) scale(.81)">${base.Icon_Strength}</g>`+badge2x+clock;
products.Cash10Min=`<g transform="translate(-3,34) scale(.81)">${base.Icon_Cash}</g>`+badge2x+clock;
products.TeamMuscleBoost=`<g transform="translate(0,7) scale(.58)">${base.Icon_Strength}</g><g transform="translate(112,7) scale(.58)">${base.Icon_Strength}</g><g transform="translate(29,90) scale(.78)">${base.Icon_Strength}</g>`;
products.QuickHint=`<g transform="translate(-12,-5) scale(.92)">${base.Icon_Hint}</g>`+group('<path d="M177 101h47l-31 51h29l-70 86l17-64h-30Z" fill="#60D6A1"/>');
products.SuperHint=group('<circle cx="108" cy="103" r="72" fill="#A5ECF4"/><circle cx="108" cy="103" r="49" fill="#FFF3B6"/>'+star(108,103,38)+'<path d="M156 151l67 66q10 14-5 24q-11 8-22-4l-65-64Z" fill="#B296F4"/><path d="M65 83q8-23 33-27" stroke="white" fill="none"/>');
for(const [k,b] of Object.entries(products))await save(ui,'Icon_Prod_'+k,b);
const notifications={Info:'<circle cx="64" cy="32" r="7" fill="white" stroke="none"/><path d="M64 55v43"/>',Success:'<path d="M28 66l24 24l49-53"/>',Warning:'<path d="M64 24v48"/><circle cx="64" cy="99" r="7" fill="white" stroke="none"/>',Error:'<path d="M33 33l62 62 M95 33L33 95"/>',Premium:star(64,64,45,'white')};
for(const [k,b] of Object.entries(notifications))await save(ui,'Icon_Notify_'+k,`<g stroke="white" stroke-width="13" fill="none" stroke-linecap="round" stroke-linejoin="round">${b}</g>`,128);
await save(ui,'Glow','<defs><radialGradient id="g"><stop stop-color="white" stop-opacity="1"/><stop offset=".18" stop-color="white" stop-opacity=".86"/><stop offset=".45" stop-color="white" stop-opacity=".4"/><stop offset=".75" stop-color="white" stop-opacity=".09"/><stop offset="1" stop-color="white" stop-opacity="0"/></radialGradient></defs><circle cx="128" cy="128" r="128" fill="url(#g)"/>');
let rays='<defs><radialGradient id="r" gradientUnits="userSpaceOnUse" cx="256" cy="256" r="256"><stop stop-color="white" stop-opacity=".9"/><stop offset=".28" stop-color="white" stop-opacity=".7"/><stop offset=".64" stop-color="white" stop-opacity=".3"/><stop offset="1" stop-color="white" stop-opacity="0"/></radialGradient><filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3"/></filter></defs><g fill="url(#r)" filter="url(#soft)">';
for(let i=0;i<16;i++){let a=i*Math.PI/8, p=(r,t)=>`${256+Math.cos(t)*r},${256+Math.sin(t)*r}`;rays+=`<path d="M256 256L${p(251,a-.055)}Q${p(255,a)} ${p(251,a+.055)}Z"/>`;}rays+='</g>';await save(ui,'Rays',rays,512);
const logo='<defs><linearGradient id="gold" x2="0" y2="1"><stop stop-color="#FFF2A8"/><stop offset=".5" stop-color="#FFD447"/><stop offset="1" stop-color="#F1A529"/></linearGradient></defs>'+text('1000',512,177,196,'url(#gold)').replace('stroke-width="6"','stroke-width="22"')+text('HIDDEN OBJECTS',512,353,88,'#FFFFFF').replace('stroke-width="6"','stroke-width="19"')+`<g transform="translate(516,52) scale(.52)">${base.Icon_Key}</g>`+group(star(112,130,21)+star(902,102,17));
await save(ui,'Logo',logo,1024,440);
const colors={DoubleCash:['#98F5BA','#24B882'],StrongerHands:['#B9A3FF','#7556DC'],FastHands:['#A4F0FF','#319BDB'],ThrowBoost:['#FFD382','#F07950'],VIP:['#E6B0FF','#8952C5'],QuickHint:['#CCF69A','#48B491'],SuperHint:['#A3E5FF','#497ADA'],Strength10Min:['#CAB2FF','#8261D8'],Cash10Min:['#A3F0BC','#39A376'],TeamMuscleBoost:['#FFBC9E','#D86C66']};
for(const [k,b] of Object.entries(products)){const [c1,c2]=colors[k];let bg=`<defs><linearGradient id="bg" x2="0" y2="1"><stop stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs><rect x="10" y="10" width="492" height="492" rx="90" fill="url(#bg)" stroke="${ink}" stroke-width="14"/><path d="M45 130Q120 32 256 45" fill="none" stroke="white" stroke-opacity=".45" stroke-width="12" stroke-linecap="round"/><circle cx="256" cy="262" r="174" fill="white" fill-opacity=".13"/><g transform="translate(40,40) scale(1.69)">${b}</g>`;await save(hub,(k in {DoubleCash:1,StrongerHands:1,FastHands:1,ThrowBoost:1,VIP:1}?'Pass_':'Product_')+k,bg,512);}
function medal(body,color='#52BAEF'){return `<circle cx="256" cy="256" r="244" fill="${ink}"/><circle cx="256" cy="256" r="225" fill="${color}" stroke="#FFF1B4" stroke-width="12"/><circle cx="256" cy="256" r="198" fill="${ink}" fill-opacity=".12"/>${group(star(83,251,19)+star(429,251,19))}${body}`;}
await save(hub,'Badge_FirstObject',medal(`<g transform="translate(35,55) scale(1.72)">${base.Icon_Key}</g>`),512);
for(const [i,name,n] of [[0,'TenObjects','10'],[1,'HundredObjects','100'],[2,'FiveHundredObjects','500'],[3,'ThousandObjects','1000']]){const sc=.78+i*.085;const trophy=group('<path d="M165 106H108v61q0 53 75 60 M347 106h57v61q0 53-75 60" fill="none" stroke-width="22"/><path d="M158 84h196v104q0 81-76 95v57h59v38H175v-38h59v-57q-76-14-76-95Z" fill="#FFC83E"/><path d="M180 103v72q0 43 29 62" fill="none" stroke="#FFF1B4" stroke-width="15"/>');let b=`<g transform="translate(${256*(1-sc)},${190*(1-sc)}) scale(${sc})">${trophy}</g>`;if(i>1)b+=group(star(256,117,27));b+=text(n,256,427,72);await save(hub,'Badge_'+name,medal(b,['#60D6A1','#52BAEF','#B296F4','#F2AD3F'][i]),512);}
await save(hub,'Badge_FirstFinderWin',medal(group('<path d="M135 377l27-137q4-25 24-20l18 39l58-63q15-17 30 0l-39 67l45-25q22-9 31 12l-34 31l26-4q29 0 27 23l-28 19q20 1 19 22q-14 47-103 57l-16 36Z" fill="#FFD18B"/>')+`<g transform="translate(98,25) scale(1.22)">${base.Icon_Key}</g>`,'#B296F4'),512);
await save(hub,'Badge_Room001Speed',medal(`<g transform="translate(30,10) scale(1.65)">${base.Icon_Key}</g><g transform="translate(28,65) scale(1.7)">${clock}</g>`,'#60D6C4'),512);
for(const [src,dest,w,h] of [
['exec-5b444066-a762-4bca-8eee-a8af9c7c6aba.png',ui+'/LoadingBackground.png',1920,1080],
['exec-76d9b9c4-2aca-4242-9765-3489ea2bee60.png',hub+'/Thumbnail_1.png',1920,1080],
['exec-7200cf51-a9dc-4e88-90eb-500418427f0b.png',hub+'/Thumbnail_2.png',1920,1080],
['exec-3fa9deaf-233c-424e-9f04-aaa5bd3ce176.png',hub+'/Thumbnail_3.png',1920,1080],
['exec-a94ad191-5bff-48d1-b8b3-17181e5fd5dc.png',hub+'/GameIcon.png',512,512]]) await sharp(gen+src).resize(w,h).png().toFile(dest);
const entries=[];for(const dir of [ui,hub])for(const file of (await fs.readdir(dir)).filter(x=>x.endsWith('.png'))){const m=await sharp(dir+'/'+file).metadata();entries.push({file:dir+'/'+file,width:m.width,height:m.height,alpha:m.hasAlpha});}
await fs.writeFile(root+'/game-art/additions/file-manifest.json',JSON.stringify(entries,null,2));
const cells=[];const thumbs=entries.filter(x=>!x.file.includes('Thumbnail')&&!x.file.includes('LoadingBackground')&&!x.file.includes('Logo'));for(let i=0;i<thumbs.length;i++){const b=await sharp(thumbs[i].file).resize(144,144,{fit:'contain',background:'#343447'}).png().toBuffer();cells.push({input:b,left:(i%7)*164+10,top:Math.floor(i/7)*185+8});let label=path.basename(thumbs[i].file,'.png').replace('Icon_Prod_','').replace('Icon_Notify_','Notify ');const l=await sharp(Buffer.from(svg(`<text x="82" y="18" text-anchor="middle" font-size="12" font-family="Arial" fill="white">${label}</text>`,164,28))).png().toBuffer();cells.push({input:l,left:(i%7)*164,top:Math.floor(i/7)*185+154});}
await sharp({create:{width:1148,height:Math.ceil(thumbs.length/7)*185,channels:4,background:'#343447'}}).composite(cells).png().toFile(root+'/game-art/additions/contact-sheet.png');
console.log(JSON.stringify({ui:entries.filter(x=>x.file.startsWith(ui)).length,creatorHub:entries.filter(x=>x.file.startsWith(hub)).length}));
}
main().catch(e=>{console.error(e);process.exitCode=1});


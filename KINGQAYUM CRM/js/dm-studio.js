import { put } from './db.js';
import { esc, make, stamp, today } from './core.js';

const SERVICES=['Graphic design','Flyers','Branding','Social media designs','Photo editing','Web design'];
const TYPES=['Cold outreach','Follow-up','Reply assistant'];
const REPLY_CATEGORIES=['Interest','Price question','Objection','Request for samples','Delayed decision','Referral','Polite rejection'];
let state={draft:'',notice:'Offline template/rule-based generation. Nothing has been sent or recorded.',status:'ready',context:null};

const value=(form,name)=>form.elements[name]?.value.trim()||'';
const sentence=value=>String(value||'').trim().replace(/\s+/g,' ');
const nameOf=prospect=>sentence(prospect?.contactName)||'there';
const businessOf=prospect=>sentence(prospect?.name)||'your business';
const serviceOf=context=>sentence(context.service)||'design support';
const concise=(text,length)=>{
  if(length!=='Short') return text;
  const parts=sentence(text).match(/[^.!?]+[.!?]+|[^.!?]+$/g)||[];
  return parts.slice(0,3).join(' ').trim();
};
const hasStopStatus=prospect=>['Rejected','Not interested'].includes(prospect?.status);

export function substitute(template,context={}){
  return template.replace(/{{(business_name|contact_name|service|designer_name)}}/g,(_,key)=>({business_name:businessOf(context),contact_name:nameOf(context),service:serviceOf(context),designer_name:context.designer||'KingQayum'}[key]));
}

export function buildContext(form,data){
  const prospect=data.prospects.find(item=>item.id===value(form,'prospectId'));
  const settings=data.settings[0]||{};
  return {
    ...prospect,
    name:value(form,'businessName')||prospect?.name||'', contactName:value(form,'contactName')||prospect?.contactName||'',
    category:value(form,'businessType')||prospect?.category||'', service:value(form,'service')||prospect?.service||'',
    opportunity:value(form,'opportunity')||prospect?.opportunity||'', actualReply:value(form,'actualReply'), replyCategory:value(form,'replyCategory'),
    scenario:value(form,'followupScenario'), tone:value(form,'tone')||'Persuasive but natural', length:value(form,'length')||'Standard',
    type:value(form,'messageType')||'Cold outreach', designer:settings.designer||'KingQayum', business:settings.business||'KingQayumEditz', prospect,
    interactions:data.interactions.filter(item=>item.prospectId===prospect?.id), followups:data.followups.filter(item=>item.prospectId===prospect?.id&&!item.completed&&!item.cancelled)
  };
}

function cold(context){
  const greeting=`Hello ${nameOf(context)},`;
  const evidence=context.opportunity?` I noticed ${sentence(context.opportunity)}.`:` I am reaching out because thoughtful visual design can make it easier for customers to understand a business.`;
  const category=context.category?` for ${context.category}`:'';
  return `${greeting}${evidence} I’m ${context.designer} from ${context.business}. I offer ${serviceOf(context)}${category}, with a focus on clear, professional visuals that fit the business. Would you be open to a brief chat about whether this could be useful for ${businessOf(context)}?`;
}
function followup(context){
  if(hasStopStatus(context.prospect)) return 'This prospect is marked as not interested or rejected, so DM Studio will not suggest a follow-up.';
  const scheduled=context.followups[0];
  const scheduleNote=scheduled?` A follow-up is already scheduled for ${scheduled.dueDate}; send only if that timing still makes sense.`:'';
  const lastReply=[...context.interactions].filter(item=>item.type==='Reply received').sort((a,b)=>String(a.date).localeCompare(String(b.date))).pop();
  const previousContext=lastReply?` Thanks for your earlier response${lastReply.date?` on ${lastReply.date}`:''}.`:context.prospect?.lastContact?` I’m following up on our last message from ${context.prospect.lastContact}.`:'';
  const scenarios={
    'Initial interest':`Thanks again for your interest in ${serviceOf(context)}. Is there a particular goal or project you would like to discuss?`,
    'Requested pricing':`Thanks for asking about pricing. The scope affects the cost, so could you share the design type, quantity or size, and what you need it to achieve? I can then give you accurate information.`,
    'Postponed decision':`Thanks for the update. I understand the timing may not be right. Would it be helpful if I checked back at a time that suits you?`,
    'Promised future opportunity':`Thank you for keeping me in mind. When the opportunity comes up, I would be glad to discuss what ${serviceOf(context)} could support for ${businessOf(context)}.`,
    'No response':`Just checking whether my earlier note about ${serviceOf(context)} was relevant to ${businessOf(context)}. No pressure at all—if now is not a good time, I’m happy to leave it there.`
  };
  return `Hello ${nameOf(context)},${previousContext} ${scenarios[context.scenario]||scenarios['No response']}${scheduleNote}`;
}
function reply(context){
  if(context.replyCategory==='Polite rejection') return `Thank you for letting me know, ${nameOf(context)}. I appreciate your time and will not follow up further. Wishing ${businessOf(context)} all the best.`;
  const actual=context.actualReply?` Thanks for sharing: “${sentence(context.actualReply)}”`:'';
  const responses={
    'Interest':`Thanks for your interest. What would you like ${serviceOf(context)} to help with, and do you have any references or priorities I should consider?`,
    'Price question':`Thanks for asking. Pricing depends on the design scope, deliverables, and any revisions needed. Could you tell me a little about the project so I can respond accurately?`,
    'Objection':`Thanks for being open about that. I understand. If you would like, you can share the concern and I will clarify what I can without making assumptions.`,
    'Request for samples':`Thanks for your interest. I can share relevant samples from my portfolio once I know which type of ${serviceOf(context)} you are considering.`,
    'Delayed decision':`Thanks for the update. Take the time you need; I’m happy to continue the conversation whenever the timing is right.`,
    'Referral':`Thank you for thinking of me. Please feel free to share my details with them, and I’ll be glad to understand their design needs if they reach out.`
  };
  return `Hello ${nameOf(context)},${actual} ${responses[context.replyCategory]||responses.Interest}`;
}

export function generateOffline(context){
  let draft=context.type==='Follow-up'?followup(context):context.type==='Reply assistant'?reply(context):cold(context);
  return concise(draft,context.length);
}

// A server-side proxy can implement this adapter later. The browser never holds
// provider secrets; callers must supply a trusted, authenticated endpoint.
export function createOnlineProvider({endpoint,fetchImpl=fetch,timeoutMs=10000}={}){
  return {async generate(payload){
    if(!endpoint) throw Error('Online provider is not configured.');
    const controller=new AbortController(), timer=setTimeout(()=>controller.abort(),timeoutMs);
    try {const response=await fetchImpl(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},credentials:'include',signal:controller.signal,body:JSON.stringify(payload)});
      if(response.status===429) throw Error('Online provider rate limit reached.');
      if(!response.ok) throw Error('Online provider is unavailable.');
      const body=await response.json();
      if(!body||typeof body.text!=='string'||!body.text.trim()) throw Error('Online provider returned an invalid response.');
      return body.text.trim();
    } catch(error) {if(error.name==='AbortError') throw Error('Online provider timed out.'); throw error} finally {clearTimeout(timer)}
  }};
}

export async function generateFromForm(data){
  const form=document.querySelector('#dmStudioForm');
  const context=buildContext(form,data);
  state.status='loading';
  state.notice='Generating a local template/rule-based draft…';
  if(value(form,'generationMode')==='Online') {
    state.notice='Online provider unavailable: this local-only checkout has no configured secure server-side proxy. A safe offline draft was generated instead.';
  } else if(!navigator.onLine) state.notice='Offline: generated locally with templates and rules. No prospect data left this device.';
  state.draft=generateOffline(context);
  state.context=context;
  state.status='ready';
}

export async function copyDraft(){
  if(!state.draft) throw Error('Generate a draft first.');
  await navigator.clipboard.writeText(state.draft);
}
export async function saveDraftTemplate(){
  if(!state.draft) throw Error('Generate a draft first.');
  await put('templates',make({name:`DM Studio ${state.context?.type||'draft'} ${today()}`,category:'DM Studio',body:state.draft}));
}
export async function recordDraft(){
  const context=state.context;
  if(!state.draft) throw Error('Generate a draft first.');
  if(!context?.prospect?.id) throw Error('Select a saved prospect before recording a real-world interaction. Temporary details are never saved automatically.');
  if(hasStopStatus(context.prospect)) throw Error('This prospect is marked as not interested or rejected. No outreach can be recorded from DM Studio.');
  if(!confirm('Record this only if you actually sent or used this message in the real world. Continue?')) return false;
  const type=context.type==='Follow-up'?'Follow-up sent':context.type==='Reply assistant'?'Reply received':'Initial message sent';
  const interaction=make({prospectId:context.prospect.id,type,date:today(),summary:state.draft,nextAction:''});
  await put('interactions',interaction);
  await put('prospects',{...context.prospect,lastContact:today(),firstContactDate:context.prospect.firstContactDate||(['Initial message sent','Follow-up sent'].includes(type)?today():''),status:type==='Initial message sent'&&context.prospect.status==='New prospect'?'Contacted':context.prospect.status,updatedAt:stamp()});
  return true;
}

export function renderDMStudio(data){
  const selected=state.context?.prospect?.id||'';
  const options=data.prospects.map(prospect=>`<option value="${esc(prospect.id)}" ${selected===prospect.id?'selected':''}>${esc(prospect.name)}${prospect.contactName?` — ${esc(prospect.contactName)}`:''}</option>`).join('');
  const templateHint=data.templates.filter(template=>template.category==='DM Studio').length;
  return `<div class="section-head"><div><h2>DM Studio</h2><span class="subtle">Draft assistance only. It never sends messages or changes a prospect until you explicitly record real contact.</span></div><span class="badge">Local-first</span></div><div class="dm-layout"><section class="card"><form id="dmStudioForm"><div class="form-grid"><div class="field full"><label>Message type</label><select name="messageType">${TYPES.map(type=>`<option ${state.context?.type===type?'selected':''}>${type}</option>`).join('')}</select></div><div class="field"><label>Saved prospect (optional)</label><select name="prospectId"><option value="">Temporary details — do not save</option>${options}</select></div><div class="field"><label>Generation mode</label><select name="generationMode"><option>Offline</option><option>Online</option></select></div><div class="field"><label>Business / prospect name</label><input name="businessName" value="${esc(state.context?.name||'')}"></div><div class="field"><label>Contact person</label><input name="contactName" value="${esc(state.context?.contactName||'')}"></div><div class="field"><label>Business type</label><input name="businessType" placeholder="e.g. restaurant, salon" value="${esc(state.context?.category||'')}"></div><div class="field"><label>Service offered</label><select name="service">${SERVICES.map(service=>`<option ${state.context?.service===service?'selected':''}>${service}</option>`).join('')}</select></div><div class="field full"><label>Observed design opportunity (only enter facts you observed)</label><textarea name="opportunity" placeholder="e.g. menu posts use inconsistent text sizes">${esc(state.context?.opportunity||'')}</textarea></div><div class="field"><label>Follow-up scenario</label><select name="followupScenario">${['No response','Initial interest','Requested pricing','Postponed decision','Promised future opportunity'].map(item=>`<option ${state.context?.scenario===item?'selected':''}>${item}</option>`).join('')}</select></div><div class="field"><label>Reply category</label><select name="replyCategory">${REPLY_CATEGORIES.map(item=>`<option ${state.context?.replyCategory===item?'selected':''}>${item}</option>`).join('')}</select></div><div class="field full"><label>Actual prospect reply (optional)</label><textarea name="actualReply" placeholder="Paste only what you want used in this draft">${esc(state.context?.actualReply||'')}</textarea></div><div class="field"><label>Tone</label><select name="tone"><option>Persuasive but natural</option><option>Warm and professional</option><option>Direct and simple</option></select></div><div class="field"><label>Length</label><select name="length"><option>Standard</option><option>Short</option></select></div></div><p class="subtle">Offline generation is reusable template/rule-based assistance, not AI. Online mode sends nothing because no trusted proxy is configured.</p><button class="primary" type="submit">Generate draft</button></form></section><section class="card dm-draft"><div class="section-head" style="margin-top:0"><h2>Editable draft</h2><span class="badge">${state.status==='loading'?'Generating…':'Offline rules'}</span></div><p class="subtle">${esc(state.notice)}</p><textarea id="dmDraft" aria-label="Editable generated message" placeholder="Your generated draft appears here">${esc(state.draft)}</textarea><div class="toolbar"><button class="secondary" data-action="dm-copy">Copy</button><button class="secondary" data-action="dm-regenerate">Regenerate</button><button class="secondary" data-action="dm-save-template">Save as template</button><button class="primary" data-action="dm-record">Record real contact</button></div><p class="subtle">${templateHint?`${templateHint} DM Studio template${templateHint===1?'':'s'} saved in Message library.`:'Saving a draft adds it to Message library; it does not log contact.'}</p></section></div>`;
}

export function syncDraftFromEditor(){ const editor=document.querySelector('#dmDraft'); if(editor) state.draft=editor.value.trim(); }

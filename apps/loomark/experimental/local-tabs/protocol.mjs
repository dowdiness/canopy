export const acceptEnvelope=(pending,message)=>!!pending&&message?.epoch===pending.epoch&&message.id===pending.id&&message.document===pending.document;
export const acceptOffer=(state,offer)=>state.revision===offer.revision&&!state.composing&&!state.editing&&!state.queued&&state.text===offer.before;
export const saved=state=>state.ready&&!state.queued&&!state.packets&&!state.failure&&!state.blocked&&!state.composing;

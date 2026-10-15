// Only this finite classifier transport is available to the pure evaluator.
export function classifierTransport(endpoint,model,fetcher=fetch,audit={classifierRequests:0,deniedRequests:0}){
 return async(url,options)=>{
  let body;try{body=JSON.parse(options.body);}catch{audit.deniedRequests++;throw Error('Non-finite provider request');}
  if(String(url)!==endpoint||options.method!=='POST'||body.model!==model||Object.keys(body).some(k=>!['state','questions','model'].includes(k))||!body.questions||Object.values(body.questions).some(q=>!['choice','noul'].includes(q.type))){audit.deniedRequests++;throw Error('Generative dispatch forbidden');}
  audit.classifierRequests++;return fetcher(url,{...options,redirect:'error'});
 };
}

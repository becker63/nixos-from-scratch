import ts from 'typescript';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname,join,basename} from 'node:path';
const dependencyModules=dirname(dirname(createRequire(import.meta.url).resolve('typescript/package.json')));
import type {Edit,FileTarget,Grammar,SymbolTarget} from './state.js';
const id=(s:string)=>createHash('sha256').update(s).digest('hex').slice(0,12);
const options:ts.CompilerOptions={strict:true,noEmit:true,allowJs:true,checkJs:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.NodeNext,moduleResolution:ts.ModuleResolutionKind.NodeNext,skipLibCheck:true,types:['node'],typeRoots:[join(dependencyModules,'@types')],allowImportingTsExtensions:true};
const declarationCache=new Map<string,ts.SourceFile>();
export function analyze(path:string,source:string,previous?:ts.Program) {
  const host=ts.createCompilerHost(options);const original=host.readFile;
  host.readFile=file=>file===path?source:original(file);
  const getSource=host.getSourceFile;host.getSourceFile=(file,version,onError,createNew)=>{if(file.endsWith('.d.ts')&&file.includes('node_modules')){const cached=declarationCache.get(file);if(cached)return cached;const parsed=getSource(file,version,onError,createNew);if(parsed)declarationCache.set(file,parsed);return parsed;}return getSource(file,version,onError,createNew);};
  host.resolveModuleNames=(names,file)=>names.map(name=>ts.resolveModuleName(name,name.startsWith('.')||name.startsWith('/')?file:join(dependencyModules,'..',basename(file)),options,host).resolvedModule);
  const program=ts.createProgram([path],options,host,previous);const file=program.getSourceFile(path);
  if(!file)throw new Error('Source unavailable');
  return {program,file,checker:program.getTypeChecker(),diagnostics:ts.getPreEmitDiagnostics(program).filter(d=>d.file?.fileName===path)};
}
export function symbols(file:FileTarget,path:string,source:string,expanded=false):SymbolTarget[] {
  const parsed=ts.createSourceFile(path,source,ts.ScriptTarget.Latest,true);
  const result:SymbolTarget[]=[];
  function visit(node:ts.Node){
    if((ts.isFunctionDeclaration(node)||ts.isMethodDeclaration(node)||expanded&&ts.isFunctionExpression(node))&&node.name)result.push({id:`S${id(file.id+node.pos)}`,file:file.id,name:node.name.getText(parsed),start:node.getStart(parsed),end:node.end,excerpt:node.getText(parsed).slice(0,768)});
    if(expanded&&ts.isVariableDeclaration(node)&&node.initializer&&(ts.isArrowFunction(node.initializer)||ts.isFunctionExpression(node.initializer)))result.push({id:'S'+id(file.id+node.pos),file:file.id,name:node.name.getText(parsed),start:node.getStart(parsed),end:node.end,excerpt:node.getText(parsed).slice(0,768)});
    ts.forEachChild(node,visit);
  }
  visit(parsed);
  if(expanded)for(const symbol of result){const references=new Set<string>();const scan=(node:ts.Node)=>{if(node.getStart(parsed)>=symbol.start&&node.end<=symbol.end&&ts.isCallExpression(node))references.add(node.expression.getText(parsed));if(node.end>=symbol.start&&node.pos<=symbol.end)ts.forEachChild(node,scan);};scan(parsed);symbol.references=[...references].slice(0,16);}
  return result.slice(0,expanded?512:32);
}
export function generateEdits(file:FileTarget,path:string,source:string,grammar:Grammar,focus?:SymbolTarget):{edits:Edit[];before:number;diagnostics:string[]} {
  const {program,file:ast,checker,diagnostics}=analyze(path,source);
  const raw:Array<Omit<Edit,'typeValid'>>=[];
  function add(node:ts.Node,family:Edit['family'],start:number,end:number,to:string,description:string){
    if(raw.length>=128||focus&&(start<focus.start||end>focus.end))return;
    const from=source.slice(start,end);if(from===to)return;
    raw.push({id:`E${id(file.id+family+start+end+to)}`,file:file.id,node:`N${id(file.id+node.pos)}`,family,start,end,from,to,description,...(grammar==='J4'?{provenance:{kind:family==='CompilerFix'?'Compiler' as const:'TypeChecker' as const,file:file.path,start:node.getStart(ast),end:node.end}}:{})});
  }
  const inScope=(node:ts.Node)=>checker.getSymbolsInScope(node,ts.SymbolFlags.Variable|ts.SymbolFlags.Function|ts.SymbolFlags.BlockScopedVariable).filter(s=>s.declarations?.some(d=>d.getSourceFile()===ast)&&/^[$a-zA-Z_][$a-zA-Z_0-9]*$/.test(s.name));
  // J4 donors are existing AST nodes. Unknown/any types never certify compatibility.
  const known=(type:ts.Type)=>!(type.flags&(ts.TypeFlags.Any|ts.TypeFlags.Unknown|ts.TypeFlags.Never));
  const compatible=(a:ts.Node,b:ts.Node)=>{const x=checker.getBaseTypeOfLiteralType(checker.getTypeAtLocation(a)),y=checker.getBaseTypeOfLiteralType(checker.getTypeAtLocation(b));return known(x)&&known(y)&&checker.isTypeAssignableTo(x,y)&&checker.isTypeAssignableTo(y,x);};
  const literals:ts.Expression[]=[],donors:ts.Expression[]=[];
  const collect=(node:ts.Node)=>{if(ts.isStringLiteral(node)||ts.isNumericLiteral(node)||node.kind===ts.SyntaxKind.TrueKeyword||node.kind===ts.SyntaxKind.FalseKeyword||node.kind===ts.SyntaxKind.NullKeyword)literals.push(node as ts.Expression);if(ts.isReturnStatement(node)&&node.expression)donors.push(node.expression);if(ts.isIfStatement(node)||ts.isConditionalExpression(node))donors.push(ts.isIfStatement(node)?node.expression:node.condition);ts.forEachChild(node,collect);};
  if(grammar==='J4')collect(ast);
  const owner=(node:ts.Node):ts.Node=>{let n=node;while(n.parent&&!ts.isFunctionLike(n))n=n.parent;return n;};
  const donorSafe=(candidate:ts.Expression,target:ts.Node)=>{
   if(owner(candidate)!==owner(target))return false;
   const allowed=new Set(inScope(target));let safe=true;
   const scan=(n:ts.Node)=>{if(ts.isIdentifier(n)&&!(ts.isPropertyAccessExpression(n.parent)&&n.parent.name===n)){const symbol=checker.getSymbolAtLocation(n);if(!symbol||!allowed.has(symbol))safe=false;}ts.forEachChild(n,scan);};scan(candidate);return safe;
  };
  function visitJ4(node:ts.Node){
   if(grammar!=='J4')return;
   const replace=(family:Edit['family'],target:ts.Node,donor:ts.Node)=>{
    const before=raw.length;add(target,family,target.getStart(ast),target.end,donor.getText(ast),`Existing compatible ${family} donor at ${donor.getStart(ast)}:${donor.end}`);
    if(raw.length>before)raw[raw.length-1].provenance={kind:'ASTDonor',file:file.path,start:donor.getStart(ast),end:donor.end};
   };
   if(ts.isStringLiteral(node)||ts.isNumericLiteral(node)||node.kind===ts.SyntaxKind.TrueKeyword||node.kind===ts.SyntaxKind.FalseKeyword||node.kind===ts.SyntaxKind.NullKeyword)for(const donor of literals.slice(0,48))if(compatible(node,donor))replace('ReplaceLiteral',node,donor);
   if(ts.isBinaryExpression(node)){
    const op=node.operatorToken,from=op.getText(ast);
    const boolean=(x:ts.Node)=>!!(checker.getTypeAtLocation(x).flags&ts.TypeFlags.BooleanLike);
    const alternatives=['&&','||'].includes(from)?['&&','||']:['===','!==','<','<=','>','>='].includes(from)&&compatible(node.left,node.right)?['===','!==','<','<=','>','>=']:[];
    if(!['&&','||'].includes(from)||boolean(node.left)&&boolean(node.right))for(const to of alternatives)add(node,'ReplaceOperator',op.getStart(ast),op.end,to,`Finite compatible operator ${from} to ${to}`);
   }
   if(ts.isPrefixUnaryExpression(node)&&node.operator===ts.SyntaxKind.ExclamationToken)replace('NegateExpression',node,node.operand);
   else if((ts.isIdentifier(node)||ts.isPropertyAccessExpression(node))&&(checker.getTypeAtLocation(node).flags&ts.TypeFlags.BooleanLike)&&!(ts.isPropertyAccessExpression(node.parent)&&node.parent.name===node))add(node,'NegateExpression',node.getStart(ast),node.end,'!'+node.getText(ast),'Negate existing boolean expression');
   if(ts.isPropertyAccessExpression(node)){
    const current=checker.getTypeAtLocation(node),objectType=checker.getTypeAtLocation(node.expression);
    if(known(current)&&known(objectType))for(const member of checker.getPropertiesOfType(objectType).slice(0,32)){
     const type=checker.getTypeOfSymbolAtLocation(member,node);
     if(member.name!==node.name.text&&/^[$a-zA-Z_][$a-zA-Z_0-9]*$/.test(member.name)&&known(type)&&checker.isTypeAssignableTo(type,current)&&checker.isTypeAssignableTo(current,type))add(node,'ReplaceMember',node.name.getStart(ast),node.name.end,member.name,`Existing TypeChecker-compatible member ${member.name}`);
    }
   }
   if(ts.isCallExpression(node)){
    const signature=checker.getResolvedSignature(node);
    for(const argument of node.arguments){
     const current=checker.getTypeAtLocation(argument);
     if(known(current))for(const symbol of inScope(argument)){const type=checker.getTypeOfSymbolAtLocation(symbol,argument);if(known(type)&&!type.getCallSignatures().length&&checker.isTypeAssignableTo(type,current))add(argument,'ReplaceArgument',argument.getStart(ast),argument.end,symbol.name,`Existing compatible in-scope argument ${symbol.name}`);}
    }
    if(signature)for(let i=0;i<node.arguments.length;i++){
     const parameter=signature.parameters[i],declaration=parameter?.valueDeclaration;
     if(i===node.arguments.length-1&&declaration&&ts.isParameter(declaration)&&(declaration.questionToken||declaration.initializer||declaration.dotDotDotToken)){const argument=node.arguments[i];add(node,'RemoveArgument',i?node.arguments[i-1].end:argument.getStart(ast),argument.end,'','Remove signature-optional trailing argument');}
    }
    for(let i=0;i<node.arguments.length;i++)for(let j=i+1;j<Math.min(node.arguments.length,4);j++)if(compatible(node.arguments[i],node.arguments[j])){
     const args=node.arguments.map(a=>a.getText(ast));[args[i],args[j]]=[args[j],args[i]];add(node,'PermuteArguments',node.arguments.pos,node.arguments.end,args.join(', '),`Permute existing compatible arguments ${i}/${j}`);
    }
   }
   const target=ts.isReturnStatement(node)?node.expression:ts.isIfStatement(node)?node.expression:ts.isConditionalExpression(node)?node.condition:undefined;
   if(target)for(const donor of donors.slice(0,48))if(donorSafe(donor,target)&&compatible(target,donor))replace(ts.isReturnStatement(node)?'ReplaceReturn':'ReplaceCondition',target,donor);
  }

  function visit(node:ts.Node){
    visitJ4(node);
    if(grammar==='J2'||grammar==='J3'||grammar==='J4') {
      if(ts.isBinaryExpression(node)) {
        const op=node.operatorToken;const from=op.getText(ast);
        const groups=[['<','<=','>','>='],['===','!=='],['==','!='],['+','-','*','/']];
        const left=checker.getTypeAtLocation(node.left),right=checker.getTypeAtLocation(node.right);
        const compatible=(left.flags&ts.TypeFlags.NumberLike)&&(right.flags&ts.TypeFlags.NumberLike);
        if(compatible)for(const to of groups.find(g=>g.includes(from))??[])add(node,'ReplaceOperator',op.getStart(ast),op.end,to,`Replace numeric binary operator ${from} with ${to}; expression ${node.getText(ast).slice(0,180)}`);
      }
      if(ts.isIdentifier(node)) {
        const parent=node.parent;
        const reference=parent&&(ts.isReturnStatement(parent)||ts.isBinaryExpression(parent)||ts.isCallExpression(parent)&&parent.arguments.some(a=>a===node)||ts.isPropertyAccessExpression(parent)&&parent.expression===node);
        if(reference) {
          const original=checker.getTypeAtLocation(node);
          if(!(original.flags&(ts.TypeFlags.Any|ts.TypeFlags.Unknown)))for(const symbol of inScope(node)) {
            const type=checker.getTypeOfSymbolAtLocation(symbol,node);
            if(symbol.name!==node.text&&type.getCallSignatures().length===0&&checker.isTypeAssignableTo(type,original)&&checker.isTypeAssignableTo(original,type))add(node,'ReplaceVariable',node.getStart(ast),node.end,symbol.name,`Use existing same-type in-scope value ${symbol.name} instead of ${node.text}`);
          }
        }
      }
      if(ts.isCallExpression(node)) {
        const signatures=checker.getTypeAtLocation(node.expression).getCallSignatures();
        const signature=signatures[0];
        if(signature&&node.arguments.length<signature.parameters.length) {
          const parameter=signature.parameters[node.arguments.length];
          const declaration=parameter.valueDeclaration;
          if(declaration&&!((ts.isParameter(declaration)&&declaration.questionToken)||ts.isParameter(declaration)&&declaration.initializer)) {
            const expected=checker.getTypeOfSymbolAtLocation(parameter,node);
            if(!(expected.flags&(ts.TypeFlags.Any|ts.TypeFlags.Unknown)))for(const symbol of inScope(node)) {
              const type=checker.getTypeOfSymbolAtLocation(symbol,node);
              if(!type.getCallSignatures().length&&checker.isTypeAssignableTo(type,expected)) {
                const insert=node.arguments.end;
                add(node,'InsertArgument',insert,insert,`${node.arguments.length?', ':''}${symbol.name}`,`Insert existing compatible argument ${symbol.name} at position ${node.arguments.length}`);
              }
            }
          }
        }
        if((grammar==='J3'||grammar==='J4')&&signature&&ts.isIdentifier(node.expression)) {
          const oldType=checker.getTypeAtLocation(node.expression);
          for(const symbol of inScope(node)) {
            const type=checker.getTypeOfSymbolAtLocation(symbol,node);
            if(symbol.name!==node.expression.text&&type.getCallSignatures().length&&checker.isTypeAssignableTo(type,oldType)&&checker.isTypeAssignableTo(oldType,type))add(node,'ReplaceCallable',node.expression.getStart(ast),node.expression.end,symbol.name,`Call existing signature-compatible helper ${symbol.name} instead of ${node.expression.text}`);
          }
        }
      }
    }
    ts.forEachChild(node,visit);
  }
  if(grammar!=='J0') {
    // Exact compiler supplied fix-its. Never apply commands or edits to other files.
    const service=ts.createLanguageService({getCompilationSettings:()=>options,getScriptFileNames:()=>[path],getScriptVersion:()=> '0',getScriptSnapshot:name=>{const text=name===path?source:ts.sys.readFile(name);return text===undefined?undefined:ts.ScriptSnapshot.fromString(text);},getCurrentDirectory:()=>ts.sys.getCurrentDirectory(),getDefaultLibFileName:o=>ts.getDefaultLibFilePath(o),fileExists:ts.sys.fileExists,readFile:ts.sys.readFile,readDirectory:ts.sys.readDirectory});
    for(const diagnostic of diagnostics.slice(0,8))if(diagnostic.start!==undefined)for(const fix of service.getCodeFixesAtPosition(path,diagnostic.start,diagnostic.start+(diagnostic.length??0),[diagnostic.code],{},{})) {
      if(fix.commands?.length||fix.changes.length!==1||fix.changes[0].fileName!==path||fix.changes[0].isNewFile||fix.changes[0].textChanges.length!==1)continue;
      const change=fix.changes[0].textChanges[0];add(ast,'CompilerFix',change.span.start,change.span.start+change.span.length,change.newText,`Compiler fix ${fix.fixName}`);
    }
    service.dispose();visit(ast);
  }
  const unique=[...new Map(raw.map(e=>[e.id,e])).values()];
  const edits:Edit[]=[];
  for(const edit of unique) {
    const patched=source.slice(0,edit.start)+edit.to+source.slice(edit.end);
    const candidate=analyze(path,patched,program);
    // Exact syntax/type evidence, not a Jev assertion of legality. Existing unrelated
    // project diagnostics are outside this deliberately single-file repair grammar.
    if(grammar==='J4'?nonWorsening(diagnostics,candidate.diagnostics)&&candidate.program.getSyntacticDiagnostics(candidate.file).length===0:candidate.diagnostics.length===0)edits.push({...edit,typeValid:true});
  }
  return {edits:edits.slice(0,64),before:unique.length,diagnostics:diagnostics.slice(0,8).map(d=>`${d.code}:${d.start??0}:${ts.flattenDiagnosticMessageText(d.messageText,' ')}`)};
}

// Source-local diagnostic multiset, ignoring offsets shifted by a legal edit.
export function nonWorsening(before:readonly ts.Diagnostic[],after:readonly ts.Diagnostic[]){
 const counts=new Map<string,number>();const key=(d:ts.Diagnostic)=>d.code+':'+ts.flattenDiagnosticMessageText(d.messageText,' ');
 for(const d of before)counts.set(key(d),(counts.get(key(d))??0)+1);
 for(const d of after){const k=key(d),n=counts.get(k)??0;if(n===0)return false;counts.set(k,n-1);}return true;
}

export function cheapLegality(path:string,before:string,after:string){
 const base=analyze(path,before),candidate=analyze(path,after,base.program);
 return candidate.program.getSyntacticDiagnostics(candidate.file).length===0&&nonWorsening(base.diagnostics,candidate.diagnostics);
}

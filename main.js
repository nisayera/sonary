(()=>{
const RM=matchMedia('(prefers-reduced-motion: reduce)').matches;
const fine=matchMedia('(pointer:fine)').matches;
const mobile=matchMedia('(max-width:900px)').matches;
const $=(s,c=document)=>c.querySelector(s),$$=(s,c=document)=>[...c.querySelectorAll(s)];

// live clock in mock menu bar
const ck=$('.clock');if(ck){const t=()=>{const d=new Date();ck.textContent=d.toLocaleDateString('en-US',{weekday:'short'})+' '+d.toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'})};t();setInterval(t,30000)}

// copy button
$$('.copy-btn').forEach(b=>b.addEventListener('click',async()=>{try{await navigator.clipboard.writeText($('#'+b.dataset.copy).textContent);b.textContent='Copied';setTimeout(()=>b.textContent='Copy',1600)}catch(e){}}));

// tile spotlight
$$('.tile').forEach(t=>t.addEventListener('pointermove',e=>{const r=t.getBoundingClientRect();t.style.setProperty('--mx',e.clientX-r.left+'px');t.style.setProperty('--my',e.clientY-r.top+'px')}));

// sonar canvas
function sonar(cv,opt={}){
  const ctx=cv.getContext('2d');let w,h,dpr,cx,cy,R,blips=[],vis=true,raf;
  const size=()=>{dpr=Math.min(devicePixelRatio||1,mobile?1.5:2);w=cv.clientWidth;h=cv.clientHeight;cv.width=w*dpr;cv.height=h*dpr;ctx.setTransform(dpr,0,0,dpr,0,0);cx=w/2;cy=opt.cy?h*opt.cy:h*.55;R=Math.hypot(w,h)*.62;
    blips=Array.from({length:mobile?14:28},()=>({a:Math.random()*Math.PI*2,r:(.15+Math.random()*.8)*R*.8,life:0}))};
  size();addEventListener('resize',size);
  new IntersectionObserver(([e])=>{vis=e.isIntersecting;if(vis&&!RM)loop()}).observe(cv);
  let ang=0,last=performance.now();
  function draw(dt){
    ctx.clearRect(0,0,w,h);
    // rings
    ctx.lineWidth=1;
    for(let i=1;i<=7;i++){ctx.beginPath();ctx.arc(cx,cy,i*R/7,0,Math.PI*2);ctx.strokeStyle=`rgba(255,255,255,${.06-i*.005})`;ctx.stroke()}
    // sweep
    const g=ctx.createConicGradient?ctx.createConicGradient(ang-Math.PI*.5,cx,cy):null;
    if(g){g.addColorStop(0,'rgba(255,79,163,0)');g.addColorStop(.3,'rgba(255,79,163,0)');g.addColorStop(.47,'rgba(255,138,61,.05)');g.addColorStop(.5,'rgba(255,79,163,.17)');g.addColorStop(.5001,'rgba(255,79,163,0)');g.addColorStop(1,'rgba(255,79,163,0)');
      ctx.fillStyle=g;ctx.beginPath();ctx.arc(cx,cy,R,0,Math.PI*2);ctx.fill()}
    // blips light up when sweep passes
    const sweepA=((ang)%(Math.PI*2)+Math.PI*2)%(Math.PI*2);
    for(const b of blips){let d=sweepA-b.a;d=((d%(Math.PI*2))+Math.PI*2)%(Math.PI*2);if(d<.05)b.life=1;b.life=Math.max(0,b.life-dt*.00045);
      if(b.life>0){const x=cx+Math.cos(b.a)*b.r,y=cy+Math.sin(b.a)*b.r;ctx.beginPath();ctx.arc(x,y,2.2,0,Math.PI*2);ctx.fillStyle=`rgba(255,200,220,${b.life*.9})`;ctx.fill();
        ctx.beginPath();ctx.arc(x,y,2+(1-b.life)*14,0,Math.PI*2);ctx.strokeStyle=`rgba(255,79,163,${b.life*.35})`;ctx.stroke()}}
    // center glow
    const rg=ctx.createRadialGradient(cx,cy,0,cx,cy,R*.5);rg.addColorStop(0,'rgba(255,79,163,.16)');rg.addColorStop(1,'rgba(255,79,163,0)');ctx.fillStyle=rg;ctx.fillRect(0,0,w,h);
  }
  function loop(){cancelAnimationFrame(raf);const f=t=>{const dt=Math.min(64,t-last);last=t;ang+=dt*.00042;draw(dt);if(vis)raf=requestAnimationFrame(f)};raf=requestAnimationFrame(f)}
  if(RM){ang=-.6;draw(0)}else loop();
}
$$('canvas.sonar').forEach((c,i)=>sonar(c,i?{cy:.5}:{cy:.52}));

// mark words for scrub heading
$$('.scrub').forEach(h=>{h.innerHTML=h.textContent.trim().split(/\s+/).map(w=>`<span class="w">${w}</span>`).join(' ')});

const ready=()=>{
  const gsap=window.gsap,ST=window.ScrollTrigger;
  if(!gsap||!ST||RM){$('.intro')?.remove();return}
  gsap.registerPlugin(ST);

  // smooth scroll
  if(window.Lenis&&!mobile){const lenis=new Lenis({lerp:.1,smoothWheel:true});lenis.on('scroll',ST.update);gsap.ticker.add(t=>lenis.raf(t*1000));gsap.ticker.lagSmoothing(0);
    $$('a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const t=$(a.getAttribute('href'));if(t){e.preventDefault();lenis.scrollTo(t,{offset:-20})}}))}

  // intro
  const tl=gsap.timeline({defaults:{ease:'expo.out'}});
  tl.from('.intro img',{scale:.6,opacity:0,duration:.7})
    .fromTo('.intro .ping',{scale:1,opacity:.9},{scale:9,opacity:0,duration:1.1,ease:'power2.out'},'-=.25')
    .to('.intro img',{scale:.8,opacity:0,duration:.4,ease:'power2.in'},'-=.8')
    .to('.intro',{opacity:0,duration:.5,onComplete:()=>$('.intro').remove()},'-=.45')
    .from('.sonar',{opacity:0,scale:1.15,duration:1.6},'-=.5')
    .from('.kicker',{y:20,opacity:0,duration:.8},'-=1.4')
    .from('h1 .ln>span',{yPercent:110,duration:1.1,stagger:.12},'-=1.3')
    .from('.lede,.ctas,.fine',{y:24,opacity:0,duration:.9,stagger:.08},'-=.8')
    .from('.nav',{y:-30,opacity:0,duration:.8},'-=.9');

  // hero parallax out
  gsap.to('.hero-inner',{yPercent:-18,opacity:0,ease:'none',scrollTrigger:{trigger:'.hero',start:'top top',end:'bottom top',scrub:true}});

  // story: pinned, dropdown opens then tabs switch
  const caps=$$('.cap'),panes=$$('.pane'),icon=$('.sicon');
  gsap.set('.dd',{clipPath:'inset(0 0 100% 0 round 20px)',y:-10,opacity:0});
  const st=gsap.timeline({scrollTrigger:{trigger:'.story',start:'top top',end:'+=260%',pin:'.story-pin',scrub:.6,anticipatePin:1,
    onUpdate:s=>{const p=s.progress;const i=p<.47?0:p<.77?1:2;caps.forEach((c,j)=>c.classList.toggle('is-on',j===i));icon.classList.toggle('on',p>.04)}}});
  st.from('.mac',{scale:.86,rotateX:14,y:60,opacity:.4,duration:.6,ease:'power2.out',transformPerspective:1400})
    .to('.dd',{clipPath:'inset(0 0 0% 0 round 20px)',y:0,opacity:1,duration:1,ease:'power3.out'})
    .to({},{duration:.6})
    .to(panes[1],{opacity:1,duration:.5}).to(panes[0],{opacity:0,duration:.3},'<').to({},{duration:.9})
    .to(panes[2],{opacity:1,duration:.5}).to(panes[1],{opacity:0,duration:.3},'<').to({},{duration:.6});

  // reveals
  ST.batch('.reveal',{start:'top 88%',onEnter:b=>gsap.to(b,{opacity:1,translate:'0 0',duration:1,ease:'expo.out',stagger:.08,overwrite:true})});
  // bento art micro motion
  gsap.from('.win-art i',{scale:.85,opacity:0,stagger:.1,duration:.8,ease:'back.out(1.6)',scrollTrigger:{trigger:'.win-art',start:'top 85%'}});
  gsap.from('kbd',{y:-30,opacity:0,stagger:.08,duration:.7,ease:'bounce.out',scrollTrigger:{trigger:'.keys',start:'top 85%'}});
  gsap.from('.pill',{width:60,duration:1,ease:'elastic.out(1,.6)',scrollTrigger:{trigger:'.notch',start:'top 85%'}});
  // word scrub
  gsap.to('.scrub .w',{opacity:1,stagger:.1,ease:'none',scrollTrigger:{trigger:'.scrub',start:'top 80%',end:'bottom 45%',scrub:true}});

  // magnetic + cursor
  if(fine){
    $$('.magnetic').forEach(el=>{const xTo=gsap.quickTo(el,'x',{duration:.5,ease:'power3'}),yTo=gsap.quickTo(el,'y',{duration:.5,ease:'power3'});
      el.addEventListener('pointermove',e=>{const r=el.getBoundingClientRect();xTo((e.clientX-r.left-r.width/2)*.3);yTo((e.clientY-r.top-r.height/2)*.4)});
      el.addEventListener('pointerleave',()=>{xTo(0);yTo(0)})});
    const cur=$('.cursor'),dot=$('.c-dot'),ring=$('.c-ring');
    const dx=gsap.quickTo(dot,'x',{duration:.08}),dy=gsap.quickTo(dot,'y',{duration:.08}),rx=gsap.quickTo(ring,'x',{duration:.45,ease:'power3'}),ry=gsap.quickTo(ring,'y',{duration:.45,ease:'power3'});
    addEventListener('pointermove',e=>{dx(e.clientX);dy(e.clientY);rx(e.clientX);ry(e.clientY)});
    document.addEventListener('pointerover',e=>cur.classList.toggle('hover',!!e.target.closest('a,button,summary')));
  }
};
if(document.readyState==='complete')ready();else addEventListener('load',ready);
})();

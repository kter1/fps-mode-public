shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 ink : source_color = vec4(0.05, 0.8, 1.0, 1.0);
uniform int graphic = 0;
uniform vec2 aspect = vec2(1.0);
uniform float phase = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float stroke(float d, float w) { return 1.0-smoothstep(w,w+0.008,abs(d)); }
void fragment() {
 vec2 p=UV*aspect;
 float art=0.0;
 vec3 base=vec3(0.004,0.007,0.024);
 if(graphic==0) {
  // Blacklight circuit mural: stepped tracks, terminals and star flecks.
  vec2 q=fract(p*2.0)-0.5;
  vec2 cell=floor(p*2.0);
  float turn=step(0.5,hash(cell+phase));
  float track=min(abs(q.y+0.16*sign(q.x)),abs(q.x-0.19*sign(q.y)));
  art=stroke(track,0.014)*0.7;
  art=max(art,stroke(length(q-vec2(0.19,-0.16))-0.075,0.012));
  art*=mix(0.35,1.0,hash(cell));
  float stars=step(0.987,hash(floor(p*25.0)+phase));
  art=max(art,stars*0.8);
  base+=vec3(0.015,0.002,0.032)*sin(p.x*2.0+p.y)*0.5;
 } else if(graphic==1) {
  // Purpose-built arcade display: pixel aliens, starfield and scanlines.
  vec2 pixel=floor(UV*vec2(48.0,40.0))+vec2(floor(sin(TIME*1.4+phase)*1.5),0.0);
  vec2 alien=mod(pixel,vec2(12.0,10.0));
  float ax=abs(alien.x-5.5);
  float body=step(1.0,alien.y)*step(alien.y,6.0)*step(ax,4.0);
  float eyes=step(abs(alien.y-3.0),0.3)*step(abs(ax-1.5),0.6);
  float legs=step(6.0,alien.y)*step(alien.y,8.0)*step(2.0,ax)*step(ax,3.0);
  art=max(body*(1.0-eyes),legs)*step(UV.y,0.78)*step(0.12,UV.y);
  base=vec3(0.004,0.015,0.035);
  art=max(art,step(0.995,hash(pixel+phase))*0.65);
  art*=0.85+0.15*sin(UV.y*500.0-TIME*12.0);
 } else if(graphic==2) {
  // UV-reactive cosmic carpet, fine enough to read as flooring.
  vec2 q=fract(p)-0.5;
  float star=stroke(q.x,0.012)*step(abs(q.y),0.08)+stroke(q.y,0.012)*step(abs(q.x),0.08);
  float orbit=stroke(length(q)-0.27,0.009)*step(0.65,hash(floor(p)));
  art=max(star,orbit)*0.3;
  base=vec3(0.008,0.007,0.025);
 } else if(graphic==4) {
  // A large ringed planet and scattered stars, painted in UV-reactive ink.
  vec2 q=(UV-0.5)*vec2(aspect.x,1.0);
  float planet=stroke(length(q)-0.29,0.012);
  vec2 tilted=mat2(vec2(0.94,0.342),vec2(-0.342,0.94))*q;
  float orbit=stroke(length(tilted*vec2(0.8,3.4))-0.47,0.012);
  float stars=step(0.987,hash(floor(UV*vec2(110.0,28.0))+phase));
  art=max(planet,orbit);
  art=max(art,stars*0.6);
  base+=vec3(0.016,0.003,0.03)*exp(-length(q)*1.3);
 } else {
  // Reactor energy: stacked telemetry rings and a moving scan.
  vec2 q=UV-0.5;
  art=stroke(length(q)-0.35,0.018)+stroke(length(q)-0.23,0.008);
  art=max(art,stroke(q.x,0.008)*step(abs(q.y),0.4));
  art+=pow(max(0.0,sin(UV.y*55.0-TIME*0.8)),24.0)*0.2;
 }
 ALBEDO=base+ink.rgb*art*(0.5+float(graphic!=2)*3.5);
 EMISSION=ink.rgb*art*(0.9+float(graphic!=2)*2.6);
}

// PS float64 implementation of display_contact.py. No fast-math or FMA.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

struct V {
    double x, y, z;
    V operator-(V b) const { return {x-b.x,y-b.y,z-b.z}; }
    V operator+(V b) const { return {x+b.x,y+b.y,z+b.z}; }
    V operator*(double s) const { return {x*s,y*s,z*s}; }
};
static V load(const double* p) { return {p[0],p[1],p[2]}; }
static double dot(V a,V b) { return (a.x*b.x+a.y*b.y)+a.z*b.z; }
static V cross(V a,V b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
static bool near(double a,double b) {
    return !std::isfinite(a) || std::abs(a-b)<=1.e-10*std::max({1.,std::abs(a),std::abs(b)});
}
static double segment2(V p,V a,V b) {
    V edge=b-a,offset=p-a;
    double len=dot(edge,edge);
    double t=len>1.e-24 ? dot(offset,edge)/len : 0.;
    V d=offset-edge*std::clamp(t,0.,1.);
    return dot(d,d);
}
static double triangle2(V p,const double* tri,bool& uncertain) {
    V a=load(tri),b=load(tri+3),c=load(tri+6);
    V ab=b-a,ac=c-a,ap=p-a,n=cross(ab,ac);
    double n2=dot(n,n),signed_d=dot(ap,n);
    double d00=dot(ab,ab),d01=dot(ab,ac),d11=dot(ac,ac);
    double d20=dot(ap,ab),d21=dot(ap,ac),denom=d00*d11-d01*d01;
    double inv=denom>1.e-24 ? 1./denom : 0.;
    double v=(d11*d20-d01*d21)*inv,w=(d00*d21-d01*d20)*inv;
    // Poorly conditioned faces use the reference NumPy calculation.
    if (denom<=1.e-12*std::max(d00*d11,1.e-24)) uncertain=true;
    double best=denom>1.e-24 && v>=0. && w>=0. && v+w<=1.
        ? (n2>1.e-24 ? signed_d*signed_d/n2 : std::numeric_limits<double>::infinity())
        : std::numeric_limits<double>::infinity();
    best=std::min(best,segment2(p,a,b));
    best=std::min(best,segment2(p,b,c));
    return std::min(best,segment2(p,c,a));
}

// All buffers are contiguous, caller-owned NumPy arrays kept alive by ctypes.
// Return uncertain points to Python for the ORIGINAL complete contact predicate.
extern "C" int display_contact_v1(
    const double* points,int64_t count,const double* triangles,int64_t triangle_count,
    const double* low,const double* high,const int32_t* children,const uint8_t* leaf,
    const int64_t* members,int64_t nodes,int64_t width,const double* direction,
    double tolerance,double hit_tolerance,uint8_t* result,uint8_t* uncertain,
    uint64_t* counters) noexcept {
    try {
        V dir=load(direction);double inv[3]={1./dir.x,1./dir.y,1./dir.z};
        double tol2=tolerance*tolerance;
        std::vector<int32_t> stack;stack.reserve(64);
        std::vector<double> hits;hits.reserve(32);
        for(int64_t i=0;i<count;++i) {
            V p=load(points+3*i);bool close=false,guard=false;
            stack.clear();stack.push_back(0);
            while(!stack.empty() && !close) {
                int32_t node=stack.back();stack.pop_back();
                if(node<0 || node>=nodes) return -2;
                V d={std::max({low[3*node]-p.x,p.x-high[3*node],0.}),
                     std::max({low[3*node+1]-p.y,p.y-high[3*node+1],0.}),
                     std::max({low[3*node+2]-p.z,p.z-high[3*node+2],0.})};
                double bound=dot(d,d);
                if(near(bound,tol2)) guard=true;
                if(bound>tol2) continue;
                if(!leaf[node]) { stack.push_back(children[2*node+1]);stack.push_back(children[2*node]);continue; }
                for(int64_t j=0;j<width;++j) {
                    int64_t t=members[node*width+j];if(t<0) continue;
                    if(t>=triangle_count) return -2;
                    ++counters[0];double dist=triangle2(p,triangles+9*t,guard);
                    if(near(dist,tol2)) guard=true;
                    if(dist<=tol2) {close=true;break;}
                }
            }
            if(!close) {
                V origin=p+dir*1.e-5;const double o[3]={origin.x,origin.y,origin.z};
                hits.clear();stack.clear();stack.push_back(0);
                while(!stack.empty()) {
                    int32_t node=stack.back();stack.pop_back();
                    if(node<0 || node>=nodes) return -2;
                    double first=-std::numeric_limits<double>::infinity();
                    double last=std::numeric_limits<double>::infinity();
                    for(int k=0;k<3;++k) {
                        double a=(low[3*node+k]-1.e-7-o[k])*inv[k];
                        double b=(high[3*node+k]+1.e-7-o[k])*inv[k];
                        first=std::max(first,std::min(a,b));last=std::min(last,std::max(a,b));
                    }
                    if(near(last,std::max(first,0.))) guard=true;
                    if(last<std::max(first,0.)) continue;
                    if(!leaf[node]) {stack.push_back(children[2*node+1]);stack.push_back(children[2*node]);continue;}
                    for(int64_t j=0;j<width;++j) {
                        int64_t t=members[node*width+j];if(t<0) continue;
                        if(t>=triangle_count) return -2;
                        ++counters[1];const double* tri=triangles+9*t;
                        V a=load(tri),e1=load(tri+3)-a,e2=load(tri+6)-a;
                        V h=cross(dir,e2);double det=dot(e1,h);
                        if(near(std::abs(det),1.e-9)) guard=true;
                        if(std::abs(det)<1.e-9) continue;
                        double r=std::abs(det)>=1.e-9 ? 1./det : 0.;
                        V offset=origin-a,q=cross(offset,e1);
                        double u=r*dot(offset,h),v=r*dot(q,dir),dist=r*dot(e2,q);
                        if(near(u,-1.e-7)||near(u,1.0000001)||near(v,-1.e-7)||
                           near(u+v,1.0000001)||near(dist,0.)) guard=true;
                        if(std::abs(det)>=1.e-9 && u>=-1.e-7 && u<=1.0000001 &&
                           v>=-1.e-7 && u+v<=1.0000001 && dist>=0.) hits.push_back(dist);
                    }
                }
                std::sort(hits.begin(),hits.end());size_t crossings=hits.empty()?0:1;
                for(size_t j=1;j<hits.size();++j) {
                    double gap=hits[j]-hits[j-1];
                    if(near(gap,hit_tolerance)) guard=true;
                    if(gap>hit_tolerance) ++crossings;
                }
                close=crossings%2!=0;
            }
            result[i]=close;uncertain[i]=guard;if(guard) ++counters[2];
        }
        return 0;
    } catch(...) { return -1; }
}

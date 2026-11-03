`timescale 1ns/1ps
// Exact lower bound in Q32 square millimetres; outward BVH bounds are safe.
module lung_point_aabb_distance_core (
 input wire clk,rst_n,start,
 input wire signed [31:0] px,py,pz,mnx,mny,mnz,mxx,mxy,mxz,
 output wire ready,output reg done,output reg [95:0] distance_q32
);
reg [2:0] state;
reg signed [32:0] dx,dy,dz;
reg [65:0] xx,yy,zz;
function automatic signed [32:0] gap(input signed [31:0] p,lo,hi);
 begin
  if(p<lo)gap=$signed({lo[31],lo})-$signed({p[31],p});
  else if(p>hi)gap=$signed({p[31],p})-$signed({hi[31],hi});
  else gap=0;
 end
endfunction
assign ready=state==0;
always @(posedge clk)begin
 if(!rst_n)begin state<=0;done<=0;distance_q32<=0;dx<=0;dy<=0;dz<=0;xx<=0;yy<=0;zz<=0;end
 else begin
  done<=0;
  case(state)
  0:if(start)begin dx<=gap(px,mnx,mxx);dy<=gap(py,mny,mxy);dz<=gap(pz,mnz,mxz);state<=1;end
  1:begin xx<=dx*dx;yy<=dy*dy;zz<=dz*dz;state<=2;end
  2:begin distance_q32<={30'd0,xx}+{30'd0,yy}+{30'd0,zz};state<=3;end
  3:begin done<=1;state<=0;end
  endcase
 end
end
endmodule

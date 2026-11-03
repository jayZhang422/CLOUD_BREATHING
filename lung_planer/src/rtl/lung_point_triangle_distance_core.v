`timescale 1ns/1ps
// Exact rational squared distance on quantized coordinates, floored to Q32.
// Degenerate triangles are treated as their three closed segments.
module lung_point_triangle_distance_core (
    input wire clk, rst_n, start,
    input wire signed [31:0] px,py,pz, ax,ay,az,bx,by,bz,cx,cy,cz,
    output wire ready, output reg done, output reg error,
    output reg [95:0] distance_q32
);
localparam IDLE=0,DOT_PREP=1,DOT_MUL=2,DOT_ADD=3,
GRAM=4,GRAM_SAVE=5,FACE_TEST=6,FACE_NUM=7,FACE_SAVE=8,
DIV_START=9,DIV_SAVE=10,EDGE_PREP=11,EDGE_TEST=12,
EDGE_NUM=13,EDGE_SAVE=14,FINISH=15,MATH_START=16,MATH_WAIT=17;
reg [4:0] state, return_state;
reg signed [32:0] e[0:2], f[0:2], w[0:2], ea[0:2], wa[0:2];
reg signed [31:0] vertices[0:8], point[0:2];
reg signed [67:0] dots[0:5]; // ee, ef, ff, we, wf, ww
reg signed [67:0] dot_acc;
reg signed [32:0] dot_a,dot_b;
reg signed [65:0] dot_product;
reg [1:0] dot_phase;
reg [2:0] dot_index;reg [1:0] axis,edge_index;reg edge_mode;
reg [2:0] operation;
reg signed [139:0] den,vn,wn,temp;
reg signed [209:0] face_numerator, edge_numerator;
reg signed [139:0] math_a;reg signed [69:0] math_b;
reg [209:0] math_numerator;reg [139:0] math_denominator;
reg math_divide;
wire math_ready,math_done;wire signed [209:0] math_result;
lung_distance_math math_unit(.clk(clk),.rst_n(rst_n),.start(state==MATH_START),
 .divide(math_divide),.a(math_a),.b(math_b),.numerator(math_numerator),
 .denominator(math_denominator),.ready(math_ready),.done(math_done),.result(math_result));
assign ready=state==IDLE;
integer i;
always @(posedge clk) begin
 if(!rst_n) begin
    state<=IDLE;done<=0;error<=0;distance_q32<={96{1'b1}};
    math_a<=0;math_b<=0;math_numerator<=0;math_denominator<=0;math_divide<=0;
    return_state<=IDLE;dot_acc<=0;dot_index<=0;axis<=0;edge_index<=0;edge_mode<=0;operation<=0;
    dot_a<=0;dot_b<=0;dot_product<=0;dot_phase<=0;
    den<=0;vn<=0;wn<=0;temp<=0;face_numerator<=0;edge_numerator<=0;
    for(i=0;i<3;i=i+1)begin e[i]<=0;f[i]<=0;w[i]<=0;ea[i]<=0;wa[i]<=0;point[i]<=0;end
    for(i=0;i<9;i=i+1)vertices[i]<=0;
    for(i=0;i<6;i=i+1)dots[i]<=0;
 end else begin
  done<=0;
  case(state)
   IDLE:if(start)begin
     point[0]<=px;point[1]<=py;point[2]<=pz;
     vertices[0]<=ax;vertices[1]<=ay;vertices[2]<=az;
     vertices[3]<=bx;vertices[4]<=by;vertices[5]<=bz;
     vertices[6]<=cx;vertices[7]<=cy;vertices[8]<=cz;
     e[0]<=$signed({bx[31],bx})-$signed({ax[31],ax});
     e[1]<=$signed({by[31],by})-$signed({ay[31],ay});
     e[2]<=$signed({bz[31],bz})-$signed({az[31],az});
     f[0]<=$signed({cx[31],cx})-$signed({ax[31],ax});
     f[1]<=$signed({cy[31],cy})-$signed({ay[31],ay});
     f[2]<=$signed({cz[31],cz})-$signed({az[31],az});
     w[0]<=$signed({px[31],px})-$signed({ax[31],ax});
     w[1]<=$signed({py[31],py})-$signed({ay[31],ay});
     w[2]<=$signed({pz[31],pz})-$signed({az[31],az});
     error<=0;distance_q32<={96{1'b1}};edge_mode<=0;edge_index<=0;dot_index<=0;
     state<=DOT_PREP;
   end
   DOT_PREP:begin dot_acc<=0;axis<=0;state<=DOT_MUL;end
   DOT_MUL:if(dot_phase==0)begin
     if(edge_mode)begin
       dot_a<=dot_index==0?ea[axis]:wa[axis];
       dot_b<=dot_index==5?wa[axis]:ea[axis];
     end else begin
       case(dot_index)
       0:begin dot_a<=e[axis];dot_b<=e[axis];end
       1:begin dot_a<=e[axis];dot_b<=f[axis];end
       2:begin dot_a<=f[axis];dot_b<=f[axis];end
       3:begin dot_a<=w[axis];dot_b<=e[axis];end
       4:begin dot_a<=w[axis];dot_b<=f[axis];end
       5:begin dot_a<=w[axis];dot_b<=w[axis];end
       endcase
     end
     dot_phase<=1;
   end else begin dot_product<=dot_a*dot_b;dot_phase<=0;state<=DOT_ADD;end
   DOT_ADD:begin
     dot_acc<=dot_acc+dot_product;
     if(axis==2)begin
       dots[dot_index]<=dot_acc+dot_product;
       if(edge_mode)begin
         if(dot_index==5)state<=EDGE_TEST;
         else begin dot_index<=dot_index==0?3:5;state<=DOT_PREP;end
       end else if(dot_index==5)begin operation<=0;state<=GRAM;end
       else begin dot_index<=dot_index+1;state<=DOT_PREP;end
     end else begin axis<=axis+1;state<=DOT_MUL;end
   end
   GRAM:begin
     math_divide<=0;
     case(operation)
     0:begin math_a<=dots[0];math_b<=dots[2];end
     1:begin math_a<=dots[1];math_b<=dots[1];end
     2:begin math_a<=dots[2];math_b<=dots[3];end
     3:begin math_a<=dots[1];math_b<=dots[4];end
     4:begin math_a<=dots[0];math_b<=dots[4];end
     5:begin math_a<=dots[1];math_b<=dots[3];end
     endcase
     return_state<=GRAM_SAVE;state<=MATH_START;
   end
   GRAM_SAVE:begin
     if(!operation[0])temp<=math_result;
     else case(operation)
       1:den<=temp-math_result;
       3:vn<=temp-math_result;
       5:wn<=temp-math_result;
     endcase
     if(operation==5)state<=FACE_TEST;
     else begin operation<=operation+1;state<=GRAM;end
   end
   FACE_TEST:begin
     if(den<0)begin error<=1;state<=FINISH;end
     else if(den!=0&&vn>=0&&wn>=0&&vn+wn<=den)begin operation<=0;state<=FACE_NUM;end
     else state<=EDGE_PREP;
   end
   FACE_NUM:begin
     math_divide<=0;
     case(operation)
      0:begin math_a<=den;math_b<=dots[5];end
      1:begin math_a<=vn;math_b<=dots[3];end
      2:begin math_a<=wn;math_b<=dots[4];end
     endcase
     return_state<=FACE_SAVE;state<=MATH_START;
   end
   FACE_SAVE:begin
     face_numerator<=operation==0?math_result:face_numerator-math_result;
     if(operation==2)state<=DIV_START;
     else begin operation<=operation+1;state<=FACE_NUM;end
   end
   DIV_START:begin
     if(face_numerator<0)begin error<=1;state<=FINISH;end
     else begin math_divide<=1;math_numerator<=face_numerator;math_denominator<=den;
       return_state<=DIV_SAVE;state<=MATH_START;end
   end
   DIV_SAVE:begin
     if(|math_result[209:96])begin error<=1;state<=FINISH;end
     else begin distance_q32<=math_result[95:0];state<=FINISH;end
   end
   EDGE_PREP:begin
     for(i=0;i<3;i=i+1)begin
       ea[i]<=$signed({vertices[(edge_index==2?0:edge_index+1)*3+i][31],vertices[(edge_index==2?0:edge_index+1)*3+i]})-
              $signed({vertices[edge_index*3+i][31],vertices[edge_index*3+i]});
       wa[i]<=$signed({point[i][31],point[i]})-$signed({vertices[edge_index*3+i][31],vertices[edge_index*3+i]});
     end
     edge_mode<=1;dot_index<=0;state<=DOT_PREP;
   end
   EDGE_TEST:begin
     if(dots[3]<=0||dots[0]==0)begin edge_numerator<=dots[5];operation<=2;state<=EDGE_SAVE;end
     else if(dots[3]>=dots[0])begin edge_numerator<=dots[5]-2*dots[3]+dots[0];operation<=2;state<=EDGE_SAVE;end
     else begin operation<=0;state<=EDGE_NUM;end
   end
   EDGE_NUM:begin
     math_divide<=0;
     math_a<=operation==0?dots[5]:dots[3];math_b<=operation==0?dots[0]:dots[3];
     return_state<=EDGE_SAVE;state<=MATH_START;
   end
   EDGE_SAVE:begin
     if(operation==0)begin edge_numerator<=math_result;operation<=1;state<=EDGE_NUM;end
     else if(operation==1)begin
       math_divide<=1;math_numerator<=edge_numerator-math_result;math_denominator<=dots[0];
       operation<=3;return_state<=EDGE_SAVE;state<=MATH_START;
     end else begin
       if(operation==2)begin
         if(edge_numerator<0|| |edge_numerator[209:96])error<=1;
         if(edge_numerator<distance_q32)distance_q32<=edge_numerator[95:0];
       end else begin
         if(|math_result[209:96])error<=1;
         if(math_result<distance_q32)distance_q32<=math_result[95:0];
       end
       if(edge_index==2)state<=FINISH;
       else begin edge_index<=edge_index+1;state<=EDGE_PREP;end
     end
   end
   MATH_START:if(math_ready)state<=MATH_WAIT;
   MATH_WAIT:if(math_done)state<=return_state;
   FINISH:begin done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
end
endmodule

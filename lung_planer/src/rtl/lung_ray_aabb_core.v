`timescale 1ns/1ps
// Sequential widened slab divider. Bounds expand in proportion to node
// extent plus two Q16 LSBs, covering the triangle barycentric tolerance. Each quotient is rounded
// outward by one t LSB, so truncation cannot discard a boundary intersection.
module lung_ray_aabb_core (
input wire clk,rst_n,s_valid, output wire s_ready,
input wire signed [31:0] ox,oy,oz,dx,dy,dz,mnx,mny,mnz,mxx,mxy,mxz,
output reg m_valid, output reg m_hit
);
reg [3:0] state;
reg [1:0] axis;
reg bound;
reg signed [31:0] origins[0:2], directions[0:2], mins[0:2], maxs[0:2];
reg signed [63:0] near_t,far_t,first_t;
reg possible;
reg [63:0] numerator,quotient;
reg [32:0] divisor;
reg [33:0] remainder;
reg [6:0] count;
reg negative;
reg signed [63:0] delta, shifted, ratio, lo,hi,pad;
reg signed [31:0] axis_origin, axis_direction, axis_min, axis_max;
reg signed [63:0] expanded_min, expanded_max;
wire [33:0] rem_next={remainder[32:0],numerator[63]};
wire qbit=rem_next>={1'b0,divisor};
assign s_ready=(state==0);
always @* begin
    shifted=delta<<<16;
    ratio=negative?-$signed(quotient):$signed(quotient);
    lo=(first_t<ratio)?first_t:ratio;
    hi=(first_t>ratio)?first_t:ratio;
end
always @(posedge clk)begin
    if(!rst_n)begin
        state<=0;
        axis<=0;
        bound<=0;
        near_t<=0;
        far_t<=0;
        first_t<=0;
        possible<=0;
        numerator<=0;
        quotient<=0;
        divisor<=0;
        remainder<=0;
        count<=0;
        negative<=0;
        m_valid<=0;
        m_hit<=0;
    end
    else begin
        m_valid<=0;
        case(state)
            0:if(s_valid)begin
                origins[0]<=ox;
                origins[1]<=oy;
                origins[2]<=oz;
                directions[0]<=dx;
                directions[1]<=dy;
                directions[2]<=dz;
                mins[0]<=mnx;
                mins[1]<=mny;
                mins[2]<=mnz;
                maxs[0]<=mxx;
                maxs[1]<=mxy;
                maxs[2]<=mxz;
                axis<=0;
                bound<=0;
                near_t<=-64'sh7fffffffffffffff;
                far_t<=64'sh7fffffffffffffff;
                possible<=1;
                state<=6;
            end
            // Register the axis mux, padding, expanded bounds and subtraction
            // separately. Keep all original 64-bit rounding/expansion semantics.
            6:begin
                axis_origin<=origins[axis]; axis_direction<=directions[axis];
                axis_min<=mins[axis]; axis_max<=maxs[axis];
                state<=7;
            end
            7:begin
                pad<=((($signed({{32{axis_max[31]}},axis_max})-
                        $signed({{32{axis_min[31]}},axis_min}))*2+65535)>>>16)+2;
                state<=8;
            end
            8:begin
                expanded_min<=$signed({{32{axis_min[31]}},axis_min})-pad;
                expanded_max<=$signed({{32{axis_max[31]}},axis_max})+pad;
                state<=9;
            end
            9:begin
                delta<=(bound?expanded_max:expanded_min)-$signed(axis_origin);
                state<=1;
            end
            1:if(axis_direction==0)begin
                if($signed(axis_origin)<expanded_min || $signed(axis_origin)>expanded_max)possible<=0;
                state<=4;
            end
            else begin
                numerator<=shifted[63]?-shifted:shifted;
                divisor<=axis_direction[31]?-$signed({axis_direction[31],axis_direction}):{1'b0,axis_direction};
                negative<=shifted[63]^axis_direction[31];
                remainder<=0;
                quotient<=0;
                count<=0;
                state<=2;
            end
            2:begin
                numerator<={numerator[62:0],1'b0};
                remainder<=qbit?rem_next-{1'b0,divisor}:rem_next;
                quotient<={quotient[62:0],qbit};
                if(count==63)state<=3;
                else count<=count+1;
            end
            3:if(!bound)begin
                first_t<=ratio;
                bound<=1;
                state<=9;
            end
            else begin
                if(lo-1>near_t)near_t<=lo-1;
                if(hi+1<far_t)far_t<=hi+1;
                state<=4;
            end
            4:if(axis==2)state<=5;
            else begin
                axis<=axis+1;
                bound<=0;
                state<=6;
            end
            5:begin
                m_valid<=1;
                m_hit<=possible&&(far_t>=0)&&(near_t<=far_t);
                state<=0;
            end
            default:state<=0;
        endcase
    end
end
endmodule

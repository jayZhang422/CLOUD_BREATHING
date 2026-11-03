`timescale 1ns/1ps
// 【文件类型：.sv】双bank缓存完整P8/P16量化token，按像素tile重排为group-major写回。
// 每bank保存16个128-bit结果；官方BRAM一拍读出，反压期间保持输出与地址。
module op_pw_pack (
    input  logic         clk_i,       // 计算时钟
    input  logic         rst_n_i,     // 异步低有效复位
    input  logic         start_i,     // 层开始，前一层必须已排空
    input  logic [30:0]  base_i,      // 输出基址
    input  logic [18:0]  pixels_i,    // 每个量化通道组的像素数
    input  logic [9:0]   cout_i,      // 有效输出通道数
    input  logic         int16_i,     // 1=P8 INT16；0=P16 INT8
    input  logic         valid_i,     // 完整128-bit量化token有效
    output logic         ready_o,     // 当前收集bank可写
    input  logic [127:0] data_i,      // P8/P16已打包为128 bit
    input  logic [18:0]  pixel_i,     // 绝对像素标签
    input  logic [6:0]   group_i,     // P8/P16输出通道组标签
    output logic         valid_o,     // 重排后的128-bit token有效
    input  logic         ready_i,     // 后台writer许可
    output logic [127:0] data_o,      // 八个INT16或十六个INT8
    output logic [30:0]  address_o,   // 保持[group][pixel]布局
    output logic         last_o,      // tile段末，冲刷半个32B字
    output logic         idle_o       // 收集与读出均排空
);
    logic write_bank_r, read_bank_r, read_active_r;
    logic [1:0] full_r;
    logic [30:0] bank_address_r [0:1];
    logic [4:0] bank_words_r [0:1];
    logic [30:0] group_address_r, tile_offset_r;
    logic [18:0] remaining_r;
    logic [4:0] tile_words_r, read_pixel_r;
    logic [6:0] last_group_r;
    logic input_fire_w, segment_end_w, read_w;
    logic [127:0] ram_data_w;

    assign ready_o = !full_r[write_bank_r];
    assign input_fire_w = valid_i && ready_o;
    assign segment_end_w = {1'b0,pixel_i[3:0]} == tile_words_r-5'd1;
    // RAM输出作为可停顿的一级缓存；阻塞时禁止下一读，载荷与标签保持。
    op_pw_pack_bram u_tiles (
        .clka(clk_i), .ena(input_fire_w), .wea(input_fire_w),
        .addra({write_bank_r,pixel_i[3:0]}), .dina(data_i),
        .clkb(clk_i), .enb(read_w), .addrb({read_bank_r,read_pixel_r[3:0]}), .doutb(ram_data_w)
    );
    assign data_o = ram_data_w;
    assign read_w = read_active_r && (!valid_o || ready_i);
    assign idle_o = full_r == 2'b00 && !read_active_r && !valid_o;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            full_r <= 2'b00; write_bank_r <= 1'b0; read_bank_r <= 1'b0;
            read_active_r <= 1'b0; read_pixel_r <= 5'd0; valid_o <= 1'b0;
            group_address_r <= 31'd0; tile_offset_r <= 31'd0;
            remaining_r <= 19'd0; tile_words_r <= 5'd0; last_group_r <= 7'd0;
        end else begin
            if (start_i) begin
                full_r <= 2'b00; write_bank_r <= 1'b0; read_bank_r <= 1'b0;
                read_active_r <= 1'b0; valid_o <= 1'b0;
                group_address_r <= base_i; tile_offset_r <= 31'd0;
                remaining_r <= pixels_i;
                tile_words_r <= pixels_i > 19'd16 ? 5'd16 : pixels_i[4:0];
                last_group_r <= int16_i ? 7'((cout_i-10'd1)>>3) : 7'((cout_i-10'd1)>>4);
            end
            if (input_fire_w && segment_end_w) begin
                full_r[write_bank_r] <= 1'b1;
                bank_address_r[write_bank_r] <= group_address_r+tile_offset_r;
                bank_words_r[write_bank_r] <= tile_words_r;
                write_bank_r <= !write_bank_r;
                if (group_i == last_group_r) begin
                    group_address_r <= base_i;
                    tile_offset_r <= tile_offset_r+{22'd0,tile_words_r,4'd0};
                    remaining_r <= remaining_r-{14'd0,tile_words_r};
                    tile_words_r <= remaining_r > 19'd32 ? 5'd16 :
                                    remaining_r > 19'd16 ? 5'(remaining_r-19'd16) : 5'd0;
                end else group_address_r <= group_address_r+{8'd0,pixels_i,4'd0};
            end
            if (!read_active_r && !valid_o && full_r[read_bank_r]) begin
                read_active_r <= 1'b1; read_pixel_r <= 5'd0;
            end
            if (read_w) begin
                valid_o <= 1'b1;
                read_pixel_r <= read_pixel_r+5'd1;
                if (read_pixel_r == bank_words_r[read_bank_r]-5'd1) read_active_r <= 1'b0;
            end else if (valid_o && ready_i) valid_o <= 1'b0;
            if (valid_o && ready_i && last_o) begin
                full_r[read_bank_r] <= 1'b0;
                read_bank_r <= !read_bank_r;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (read_w) begin
            address_o <= bank_address_r[read_bank_r]+{22'd0,read_pixel_r,4'd0};
            last_o <= read_pixel_r == bank_words_r[read_bank_r]-5'd1;
        end
    end
endmodule

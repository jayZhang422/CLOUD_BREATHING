//========================================================================================
// 文件类型: .sv (SystemVerilog)
// 模块功能: RGMII协议V1收发；DDR_ENABLE开启缓存提交/写确认/整图CRC接口
//
// 硬件平台: RK-XCKU5P-F V1.2
//   FPGA:  XCKU5P-2FFVB676I (Kintex UltraScale+)
//   PHY:   RTL8211F-CG (RGMII, 10/100/1000 Mbps)
//   时钟:  125MHz 来自PHY的eth_rxc (K22引脚)
//
// 微架构:
//   RGMII PHY ↔ rgmii_rx/rgmii_tx ↔ GMII ↔ udp_rx/udp_tx ↔ protocol_parser/builder
//
// 当前阶段目标:
//   ✓ PC ↔ FPGA 以太网通信
//   ✓ 协议帧解析（IMAGE_BEGIN/DATA/BATCH_END/IMAGE_END/INFER_TRIGGER）
//   ✓ 缺包检测与位图生成
//   ✓ 自动回复；未接DDR/模型时返回明确错误状态
//   ✗ DDR写入（暂缓，IMAGE_DATA包接收后直接丢弃，但更新位图）
//
// 验证路径:
//   L1: ARP解析192.168.1.10（当前通信顶层不提供ICMP ping）
//   L2: IMAGE_BEGIN → ACK(ACCEPTED)
//   L3: 256×IMAGE_DATA → 位图全1
//   L4: BATCH_END → BATCH_STATUS(无缺包)
//   L5: 故意丢包 → 位图正确 + 重传成功
//========================================================================================

module eth_rgmii_endpoint #(
    parameter bit DDR_ENABLE = 1'b0, // 单独通信顶层默认保持原有行为
    parameter bit OP_ENABLE = 1'b0
) (
    //===================================================================================
    // 系统复位（来自按键，低有效）
    //===================================================================================
    input  logic        sys_rst_n,           // K9引脚

    //===================================================================================
    // 以太网RGMII接口（对应top_constraint.xdc第121-160行）
    //===================================================================================
    // RX（接收，来自PHY）
    input  logic        eth_rxc,             // K22: 125MHz时钟（PHY提供）
    input  logic        eth_rx_ctl,          // K23: RX控制信号
    input  logic [3:0]  eth_rxd,             // K26/K25/L25/L24: RX数据[3:0]

    // TX（发送，到PHY）
    output logic        eth_txc,             // M25: 125MHz时钟（FPGA输出）
    output logic        eth_tx_ctl,          // M26: TX控制信号
    output logic [3:0]  eth_txd,             // K20/L20/L22/L23: TX数据[3:0]

    output logic        ddr_rx_clk_o,       // DDR连接模块接收时钟域
    output logic        ddr_rx_rst_n_o,     // 同步释放的接收域复位
    output logic        ddr_body_en_o,      // IMAGE_DATA body字节
    output logic [15:0] ddr_body_cnt_o,
    output logic [7:0]  ddr_body_data_o,
    input  logic        ddr_ready_i,
    input  logic        ddr_capture_ok_i,
    input  logic        ddr_packet_done_i,
    input  logic        ddr_packet_error_i,
    input  logic        ddr_verify_done_i,
    input  logic        ddr_verify_error_i,
    input  logic [31:0] ddr_verify_crc_i,
    output logic        ddr_packet_submit_o,
    output logic [30:0] ddr_packet_addr_o,
    output logic        ddr_verify_start_o,
    output logic [30:0] ddr_image_addr_o,
    output logic [31:0] ddr_image_bytes_o,
    output logic        ddr_error_o,
    output logic        op_frame_valid_o,
    output logic [7:0]  op_msg_o,
    output logic [31:0] op_id_o, op_sequence_o,
    output logic [15:0] op_body_len_o,
    output logic        op_body_en_o,
    output logic [15:0] op_body_count_o,
    output logic [7:0]  op_body_data_o,
    output logic        op_legacy_idle_o,
    output logic        op_image_ready_o,
    output logic [30:0] op_image_base_o,
    output logic [31:0] op_image_slices_o,
    input logic         op_block_i, op_accept_i, op_tx_start_i,
    input logic [7:0]   op_tx_data_i,
    input logic [15:0]  op_tx_len_i,
    output logic        op_tx_req_o, op_tx_done_o
);

//========================================================================================
// 参数与常量
//========================================================================================
localparam logic [47:0] BOARD_MAC = 48'h00_11_22_33_44_55;  // FPGA MAC地址
localparam logic [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10}; // 192.168.1.10

//========================================================================================
// 内部信号：GMII接口（RGMII ↔ GMII转换后）
//========================================================================================
logic        gmii_rx_clk;      // GMII RX时钟（125MHz，来自rgmii_rx的BUFG输出）
logic        gmii_rx_dv;       // GMII RX数据有效
logic [7:0]  gmii_rxd;         // GMII RX数据

logic        rgmii_clk_w;
logic        rx_clk_locked_w;
logic        rx_clk_fb_w;
logic        rx_clk_fb_buf_w;
logic        rx_reset_n_w;
logic        gmii_tx_clk;      // GMII TX时钟（125MHz，同gmii_rx_clk）
logic        gmii_tx_en;       // GMII TX使能
logic [7:0]  gmii_txd;         // GMII TX数据

//========================================================================================
// 内部信号：UDP层
//========================================================================================
logic        udp_rx_done;
logic        udp_rx_en;
logic [7:0]  udp_rx_data;
logic [15:0] udp_rx_bytes;

logic        udp_tx_req;
logic        udp_tx_done;
logic [7:0]  udp_tx_data;
logic [15:0] udp_tx_len;
logic        udp_tx_start;
logic        udp_mac_start_r;
logic        udp_gmii_en;
logic [7:0]  udp_gmii_data;
logic [47:0] udp_src_mac;
logic [31:0] udp_src_ip;
logic [15:0] udp_src_port;
logic [47:0] reply_mac_r;
logic [31:0] reply_ip_r;
logic [15:0] reply_port_r;
logic        response_accept;
logic core_accept_w, core_busy_w, core_tx_start_w, tx_op_r;
logic [7:0] core_tx_data_w;
logic [15:0] core_tx_len_w;

always_ff @(posedge gmii_rx_clk) begin
    if (response_accept) begin
        reply_mac_r  <= udp_src_mac;
        reply_ip_r   <= udp_src_ip;
        reply_port_r <= udp_src_port;
    end
end

//========================================================================================
// 内部信号：协议层
//========================================================================================
logic        frame_valid;
logic        frame_error;
logic [7:0]  rx_msg_type;
logic [31:0] rx_transfer_id;
logic [31:0] rx_sequence;
logic [15:0] rx_body_len;
logic        body_en;
logic [7:0]  body_data;
logic [15:0] body_cnt;

logic [7:0]  tx_msg_type;
logic        tx_frame_done;
logic [31:0] rx_pkt_cnt;
logic [31:0] rx_bad_crc_cnt;
logic [15:0] rx_batch_cnt;

assign response_accept = core_accept_w || (OP_ENABLE && op_accept_i);
assign udp_tx_start = core_tx_start_w || (OP_ENABLE && op_tx_start_i);
assign udp_tx_data = tx_op_r ? op_tx_data_i : core_tx_data_w;
assign udp_tx_len = OP_ENABLE && op_tx_start_i ? op_tx_len_i : core_tx_len_w;
assign op_tx_req_o = OP_ENABLE && tx_op_r && udp_tx_req;
assign op_tx_done_o = OP_ENABLE && tx_op_r && udp_tx_done;
assign op_frame_valid_o = frame_valid;
assign op_msg_o = rx_msg_type; assign op_id_o = rx_transfer_id; assign op_sequence_o = rx_sequence;
assign op_body_len_o = rx_body_len; assign op_body_en_o = body_en;
assign op_body_count_o = body_cnt; assign op_body_data_o = body_data;
assign op_legacy_idle_o = !core_busy_w && (!DDR_ENABLE || ddr_ready_i || (OP_ENABLE && op_block_i));


//========================================================================================
// 复位同步（125MHz域）
//========================================================================================
(* ASYNC_REG = "TRUE" *) logic rst_n_sync1, rst_n_sync2;
assign rx_reset_n_w = sys_rst_n && rx_clk_locked_w;

always_ff @(posedge gmii_rx_clk or negedge rx_reset_n_w) begin
    if (!rx_reset_n_w) begin
        rst_n_sync1 <= 1'b0;
        rst_n_sync2 <= 1'b0;
    end else begin
        rst_n_sync1 <= 1'b1;
        rst_n_sync2 <= rst_n_sync1;
    end
end

//========================================================================================
// 模块例化：RGMII → GMII 转换（例程原有模块）
// 注意：rgmii_rx内部有BUFG，会输出经过缓冲的gmii_rx_clk，不能在顶层直接赋值
//========================================================================================
// 补偿全局时钟插入延时，并后移1ns采样，使建立/保持窗口均留有余量。
// 125MHz -> 1000MHz VCO -> 125MHz，所有协议逻辑仍在单一时钟域。
MMCME4_BASE #(
    .CLKIN1_PERIOD    (8.000),
    .CLKFBOUT_MULT_F  (8.000),
    .DIVCLK_DIVIDE    (32'd1),
    .CLKOUT0_DIVIDE_F (8.000),
    .CLKOUT0_PHASE    (45.000)
) u_rx_mmcm (
    .CLKIN1 (eth_rxc),
    .CLKFBIN(rx_clk_fb_buf_w),
    .CLKFBOUT(rx_clk_fb_w),
    .CLKOUT0(rgmii_clk_w),
    .LOCKED (rx_clk_locked_w),
    .RST    (~sys_rst_n),
    .PWRDWN (1'b0)
);
BUFG u_rx_feedback_buf (.I(rx_clk_fb_w), .O(rx_clk_fb_buf_w));

rgmii_rx u_rgmii_rx (
    .rgmii_rxc   (rgmii_clk_w ),   // 经MMCM补偿的RGMII RX时钟
    .rgmii_rx_ctl(eth_rx_ctl  ),   // RGMII RX控制
    .rgmii_rxd   (eth_rxd     ),   // RGMII RX数据[3:0]
    .gmii_rx_clk (gmii_rx_clk ),   // GMII RX时钟输出（内部BUFG处理）
    .gmii_rx_dv  (gmii_rx_dv  ),   // GMII RX数据有效
    .gmii_rxd    (gmii_rxd    )    // GMII RX数据[7:0]
);

//========================================================================================
// 时钟分配：TX时钟使用RX模块输出的时钟（已经过BUFG）
//========================================================================================
assign ddr_rx_clk_o = gmii_rx_clk;
assign ddr_rx_rst_n_o = rst_n_sync2;
assign ddr_body_en_o = body_en && rx_msg_type == 8'h01 && (!OP_ENABLE || !op_block_i);
assign ddr_body_cnt_o = body_cnt;
assign ddr_body_data_o = body_data;
assign gmii_tx_clk = gmii_rx_clk;  // TX与RX同域

rgmii_tx u_rgmii_tx (
    .gmii_tx_clk (gmii_tx_clk ),   // GMII TX时钟
    .gmii_tx_en  (gmii_tx_en  ),   // GMII TX使能
    .gmii_txd    (gmii_txd    ),   // GMII TX数据[7:0]
    .rgmii_txc   (            ),   // 悬空，不使用rgmii_tx内部的简单赋值
    .rgmii_tx_ctl(eth_tx_ctl  ),   // RGMII TX控制
    .rgmii_txd   (eth_txd     )    // RGMII TX数据[3:0]
);

//========================================================================================
// eth_txc时钟输出：使用ODDRE1将gmii_tx_clk转发到输出PAD
// 原因：UltraScale+中，BUFG输出不能直接连接PAD，需要用DDR原语
// PHY的TXDLY绑带上拉，内部延迟采样时钟；这里转发与数据同相的时钟
//========================================================================================
ODDRE1 #(
    .IS_C_INVERTED  (1'b0),           // 时钟不反相
    .IS_D1_INVERTED (1'b0),
    .IS_D2_INVERTED (1'b0),
    .SIM_DEVICE     ("ULTRASCALE_PLUS"),
    .SRVAL          (1'b0)
) u_eth_txc_oddr (
    .Q   (eth_txc      ),   // 输出到M25引脚
    .C   (gmii_tx_clk  ),   // 125MHz时钟
    .D1  (1'b1         ),   // 上升沿输出1
    .D2  (1'b0         ),   // 下降沿输出0，形成125MHz时钟
    .SR  (1'b0         )    // 不复位
);

//========================================================================================
// 模块例化：UDP接收（例程原有模块）
//========================================================================================
udp_rx #(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP ),
    .BOARD_PORT(16'd8080),
    .CHECK_PORT(1'b1)
) u_udp_rx (
    .clk          (gmii_rx_clk   ),
    .rst_n        (rst_n_sync2   ),
    .gmii_rx_dv   (gmii_rx_dv    ),
    .gmii_rxd     (gmii_rxd      ),
    .rec_pkt_done (udp_rx_done   ),
    .rec_en       (udp_rx_en     ),
    .rec_data     (udp_rx_data   ),
    .rec_byte_num (udp_rx_bytes  ),
    .src_mac      (udp_src_mac   ),
    .src_ip       (udp_src_ip    ),
    .src_port     (udp_src_port  )
);

//========================================================================================
// 模块例化：协议解析器（新增，已验证）
//========================================================================================
protocol_parser u_parser (
    .clk_i          (gmii_rx_clk    ),
    .rst_n_i        (rst_n_sync2    ),
    .udp_rx_en_i    (udp_rx_en      ),
    .udp_rx_data_i  (udp_rx_data    ),
    .udp_rx_done_i  (udp_rx_done    ),
    .udp_rx_bytes_i (udp_rx_bytes   ),
    .frame_valid_o  (frame_valid    ),
    .frame_error_o  (frame_error    ),
    .msg_type_o     (rx_msg_type    ),
    .transfer_id_o  (rx_transfer_id ),
    .sequence_o     (rx_sequence    ),
    .body_len_o     (rx_body_len    ),
    .body_en_o      (body_en        ),
    .body_data_o    (body_data      ),
    .body_cnt_o     (body_cnt       )
);

//========================================================================================
// 模块例化：协议处理核心（从eth_top.sv移植，不含DDR）
//========================================================================================
eth_protocol_core #(.DDR_ENABLE(DDR_ENABLE)) u_protocol_core (
    .clk_i              (gmii_rx_clk      ),
    .rst_n_i            (rst_n_sync2      ),

    // 来自parser
    .frame_valid_i      (frame_valid && (!OP_ENABLE || (!op_block_i && !(rx_msg_type >= 8'h20 && rx_msg_type <= 8'h29)))),
    .frame_error_i      (frame_error      ),
    .msg_type_i         (rx_msg_type      ),
    .transfer_id_i      (rx_transfer_id   ),
    .sequence_i         (rx_sequence      ),
    .body_len_i         (rx_body_len      ),
    .body_en_i          (body_en          ),
    .body_data_i        (body_data        ),
    .body_cnt_i         (body_cnt         ),

    // 发送接口
    .udp_tx_req_i       (udp_tx_req && !tx_op_r),
    .udp_tx_done_i      (udp_tx_done && !tx_op_r),
    .udp_tx_start_o     (core_tx_start_w),
    .udp_tx_data_o      (core_tx_data_w),
    .udp_tx_len_o       (core_tx_len_w),
    .response_accept_o  (core_accept_w),
    .response_busy_o    (core_busy_w),
    .image_ready_o      (op_image_ready_o),
    .image_base_o       (op_image_base_o),
    .image_slices_o     (op_image_slices_o),

    .ddr_ready_i         (ddr_ready_i),
    .ddr_capture_ok_i    (ddr_capture_ok_i),
    .ddr_packet_done_i   (ddr_packet_done_i),
    .ddr_packet_error_i  (ddr_packet_error_i),
    .ddr_verify_done_i   (ddr_verify_done_i),
    .ddr_verify_error_i  (ddr_verify_error_i),
    .ddr_verify_crc_i    (ddr_verify_crc_i),
    .ddr_packet_submit_o (ddr_packet_submit_o),
    .ddr_packet_addr_o   (ddr_packet_addr_o),
    .ddr_verify_start_o  (ddr_verify_start_o),
    .ddr_image_addr_o    (ddr_image_addr_o),
    .ddr_image_bytes_o   (ddr_image_bytes_o),
    .ddr_error_o         (ddr_error_o),

    // 调试端口（悬空）
    .rx_msg_type_o      (                 ),
    .rx_frame_valid_o   (                 ),
    .rx_frame_error_o   (                 ),
    .tx_msg_type_o      (                 ),
    .tx_frame_done_o    (                 ),
    .rx_pkt_cnt_o       (                 ),
    .rx_bad_crc_cnt_o   (                 ),
    .rx_batch_cnt_o     (                 )
);

//========================================================================================
// 模块例化：UDP发送（例程原有模块）
//========================================================================================
logic [31:0] eth_crc_data;
logic [31:0] eth_crc_next;
logic        eth_crc_en;
logic        eth_crc_clr;

udp_tx #(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP ),
    .SRC_PORT  (16'd8080),
    .DES_PORT  (16'd8080),
    .DYNAMIC_PORT(1'b1)
) u_udp_tx (
    .clk         (gmii_tx_clk     ),
    .rst_n       (rst_n_sync2     ),
    .tx_start_en (udp_mac_start_r),
    .tx_data     (udp_tx_data     ),
    .tx_byte_num (udp_tx_len      ),
    .des_mac     (reply_mac_r     ),
    .des_ip      (reply_ip_r      ),
    .des_port    (reply_port_r    ),
    .crc_data    (eth_crc_data    ),
    .crc_next    (eth_crc_next[31:24]),
    .tx_done     (udp_tx_done     ),
    .tx_req      (udp_tx_req      ),
    .gmii_tx_en  (udp_gmii_en     ),
    .gmii_txd    (udp_gmii_data   ),
    .crc_en      (eth_crc_en      ),
    .crc_clr     (eth_crc_clr     )
);

// 以太网FCS引擎（例程原有，仅用于以太帧校验，与协议CRC无关）
crc32_d8 u_eth_fcs (
    .clk      (gmii_tx_clk  ),
    .rst_n    (rst_n_sync2  ),
    .data     (gmii_txd     ),
    .crc_en   (eth_crc_en   ),
    .crc_clr  (eth_crc_clr  ),
    .crc_data (eth_crc_data ),
    .crc_next (eth_crc_next )
);

// ARP请求排队；整个发送帧保持独占，帧间保留至少12字节时间。
logic arp_rx_done, arp_rx_type, arp_tx_done;
logic arp_gmii_en, arp_start_r, arp_pending_r;
logic [7:0] arp_gmii_data;
logic [47:0] arp_src_mac, arp_pending_mac_r, arp_reply_mac_r;
logic [31:0] arp_src_ip, arp_pending_ip_r, arp_reply_ip_r;
logic [3:0] gap_cnt_r;
typedef enum logic [1:0] {TX_IDLE, TX_ARP, TX_UDP, TX_GAP} tx_state_t;
tx_state_t tx_state_r, tx_state_nxt;

arp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_arp (
    .rst_n(rst_n_sync2),
    .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
    .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(arp_gmii_en), .gmii_txd(arp_gmii_data),
    .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
    .src_mac(arp_src_mac), .src_ip(arp_src_ip),
    .arp_tx_en(arp_start_r), .arp_tx_type(1'b1),
    .des_mac(arp_reply_mac_r), .des_ip(arp_reply_ip_r), .tx_done(arp_tx_done)
);

always_comb begin
    tx_state_nxt = tx_state_r;
    case (tx_state_r)
        TX_IDLE: begin
            if (arp_pending_r) tx_state_nxt = TX_ARP;
            else if (udp_tx_start) tx_state_nxt = TX_UDP;
        end
        TX_ARP: if (arp_tx_done) tx_state_nxt = TX_GAP;
        TX_UDP: if (udp_tx_done) tx_state_nxt = TX_GAP;
        TX_GAP: if (gap_cnt_r == 4'd11) tx_state_nxt = TX_IDLE;
        default: tx_state_nxt = TX_IDLE;
    endcase
    gmii_tx_en = 1'b0;
    gmii_txd = 8'd0;
    case (tx_state_r)
        TX_ARP: begin gmii_tx_en = arp_gmii_en; gmii_txd = arp_gmii_data; end
        TX_UDP: begin gmii_tx_en = udp_gmii_en; gmii_txd = udp_gmii_data; end
        default: ;
    endcase
end

always_ff @(posedge gmii_tx_clk or negedge rst_n_sync2) begin
    if (!rst_n_sync2) begin
        tx_state_r <= TX_IDLE;
        tx_op_r <= 1'b0;
        arp_start_r <= 1'b0;
        udp_mac_start_r <= 1'b0;
        arp_pending_r <= 1'b0;
        gap_cnt_r <= 4'd0;
    end else begin
        tx_state_r <= tx_state_nxt;
        if (tx_state_r == TX_IDLE && tx_state_nxt == TX_UDP) tx_op_r <= OP_ENABLE && op_tx_start_i;
        arp_start_r <= (tx_state_r == TX_IDLE && tx_state_nxt == TX_ARP);
        udp_mac_start_r <= (tx_state_r == TX_IDLE && tx_state_nxt == TX_UDP);
        if (tx_state_r == TX_IDLE && tx_state_nxt == TX_ARP)
            arp_pending_r <= 1'b0;
        if (arp_rx_done && !arp_rx_type)
            arp_pending_r <= 1'b1;
        if (tx_state_r == TX_GAP) gap_cnt_r <= gap_cnt_r + 4'd1;
        else gap_cnt_r <= 4'd0;
    end
end

always_ff @(posedge gmii_tx_clk) begin
    if (arp_rx_done && !arp_rx_type) begin
        arp_pending_mac_r <= arp_src_mac;
        arp_pending_ip_r <= arp_src_ip;
    end
    if (tx_state_r == TX_IDLE && tx_state_nxt == TX_ARP) begin
        arp_reply_mac_r <= arp_pending_mac_r;
        arp_reply_ip_r <= arp_pending_ip_r;
    end
end

endmodule

// 原独立通信顶层：仅保留板级引脚，DDR新增接口不成为未约束I/O。
module eth_rgmii_top (
    input  logic       sys_rst_n,
    input  logic       eth_rxc,
    input  logic       eth_rx_ctl,
    input  logic [3:0] eth_rxd,
    output logic      eth_txc,
    output logic      eth_tx_ctl,
    output logic [3:0] eth_txd
);
    eth_rgmii_endpoint #(.DDR_ENABLE(1'b0)) u_endpoint (
        .sys_rst_n(sys_rst_n), .eth_rxc(eth_rxc), .eth_rx_ctl(eth_rx_ctl), .eth_rxd(eth_rxd),
        .eth_txc(eth_txc), .eth_tx_ctl(eth_tx_ctl), .eth_txd(eth_txd),
        .ddr_rx_clk_o(), .ddr_rx_rst_n_o(), .ddr_body_en_o(), .ddr_body_cnt_o(), .ddr_body_data_o(),
        .ddr_ready_i(1'b0), .ddr_capture_ok_i(1'b0), .ddr_packet_done_i(1'b0),
        .ddr_packet_error_i(1'b0), .ddr_verify_done_i(1'b0), .ddr_verify_error_i(1'b0),
        .ddr_verify_crc_i(32'd0), .ddr_packet_submit_o(), .ddr_packet_addr_o(),
        .ddr_verify_start_o(), .ddr_image_addr_o(), .ddr_image_bytes_o(), .ddr_error_o()
    );
endmodule


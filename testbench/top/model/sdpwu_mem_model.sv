// SDPWU 的"外部存储器"模型 (只有仿真用)
//   - 写端口: 一拍写入一个 16B 条目 (tb 用它布置页表)
//   - 读端口: 收到 pw_mem_raddr_valid 后, 随机等 0..LAT_MAX 拍再给 pw_mem_raddr_ready;
//     握手后下一拍在数据通道返回读出的条目 (按 raddr_id 带回)
//   - 没写过的地址读回 0
//
// 注意: 模块内部不带 l1_base. 页表基地址是软件配置 (SDecoder_PTBR), DUT 侧由 tb 给;
//       这个模型只按绝对地址存取, 谁来算条目地址由用例决定.
module sdpwu_mem_model
import sdecoder_pkg::*;
#(
    parameter int unsigned LAT_MAX = 3      // 读地址通道随机等待 0..LAT_MAX 拍
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // 写端口: 一拍写入一个条目 (16B 对齐)
    input  logic                            pw_mem_wen,
    input  logic [PA_WIDTH-1:0]             pw_mem_waddr,
    input  logic [PW_RDATA_WIDTH-1:0]       pw_mem_wdata,

    // 读地址通道
    input  logic                            pw_mem_raddr_valid,
    input  logic [PA_WIDTH-1:0]             pw_mem_raddr,
    input  logic [PW_ID_WIDTH-1:0]          pw_mem_raddr_id,
    output logic                            pw_mem_raddr_ready,

    // 读数据通道
    output logic [PW_RDATA_WIDTH-1:0]       pw_mem_rdata,
    output logic [PW_ID_WIDTH-1:0]          pw_mem_rdata_id,
    output logic                            pw_mem_rdata_valid,
    output logic [PW_RDATA_ERR_WIDTH-1:0]   pw_mem_rdata_err,
    input  logic                            pw_mem_rdata_ready
);

    // 按 16B 对齐的地址索引; 未写过的地址读回 0
    logic [PW_RDATA_WIDTH-1:0]  mem [bit [PA_WIDTH-1:0]];

    typedef enum logic [1:0] {
        M_IDLE,
        M_WAIT,
        M_ACK,
        M_DATA
    } state_e;

    state_e                     state;
    int unsigned                wait_cnt;
    logic [PA_WIDTH-1:0]        addr_q;
    logic [PW_ID_WIDTH-1:0]     id_q;
    logic [PW_RDATA_WIDTH-1:0]  rdata_q;

    function automatic logic [PW_RDATA_WIDTH-1:0] read_mem(input logic [PA_WIDTH-1:0] addr);
        bit [PA_WIDTH-1:0] key;
        key = addr & ~48'hf;
        if (mem.exists(key)) begin
            return mem[key];
        end
        return '0;
    endfunction

    // 写端口: 一拍写入, 与读状态机并行
    always_ff @(posedge clk) begin
        if (pw_mem_wen) begin
            mem[pw_mem_waddr & ~48'hf] <= pw_mem_wdata;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= M_IDLE;
            wait_cnt           <= 0;
            addr_q             <= '0;
            id_q               <= '0;
            rdata_q            <= '0;
            pw_mem_raddr_ready <= 1'b0;
            pw_mem_rdata_valid <= 1'b0;
            pw_mem_rdata       <= '0;
            pw_mem_rdata_id    <= '0;
            pw_mem_rdata_err   <= '0;
        end
        else begin
            case (state)
                M_IDLE: begin
                    pw_mem_raddr_ready <= 1'b0;
                    pw_mem_rdata_valid <= 1'b0;
                    if (pw_mem_raddr_valid) begin
                        addr_q   <= pw_mem_raddr;
                        id_q     <= pw_mem_raddr_id;
                        wait_cnt <= $urandom_range(0, LAT_MAX);
                        state    <= M_WAIT;
                    end
                end

                M_WAIT: begin
                    if (wait_cnt == 0) begin
                        pw_mem_raddr_ready <= 1'b1;     // 本拍握手
                        rdata_q            <= read_mem(addr_q);
                        state              <= M_ACK;
                    end
                    else begin
                        wait_cnt <= wait_cnt - 1;
                    end
                end

                M_ACK: begin
                    pw_mem_raddr_ready <= 1'b0;
                    pw_mem_rdata       <= rdata_q;
                    pw_mem_rdata_id    <= id_q;
                    pw_mem_rdata_err   <= '0;
                    pw_mem_rdata_valid <= 1'b1;
                    state              <= M_DATA;
                end

                M_DATA: begin
                    if (pw_mem_rdata_ready) begin
                        pw_mem_rdata_valid <= 1'b0;
                        state              <= M_IDLE;
                    end
                end

                default: begin
                    state <= M_IDLE;
                end
            endcase
        end
    end

endmodule

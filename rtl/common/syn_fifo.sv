`default_nettype none

// 同步 FIFO (单时钟域, 首字直通 FWFT):
//   - 只要 !empty, rd_data 就一直指向队头; rd_en 把它取走 (没有读 valid, 所以做成直通)
//   - 深度与两个 almost 阈值都是参数, 例化时按场景裁剪
//   - wr_en 在 full 时忽略, rd_en 在 empty 时忽略; 上游按 full / empty 自己保证不越界
//   - 存储用寄存器堆 (深度通常很小, 不做 RAM 推断)
//   - empty 时 rd_data 是无效的旧值 (内容 X 或上次读出的数据), 调用方必须先看 empty
module syn_fifo #(
    parameter int unsigned WIDTH              = 8,
    parameter int unsigned DEPTH              = 4,
    parameter int unsigned ALMOST_FULL_LEVEL  = (DEPTH > 1) ? (DEPTH - 1) : 1,
    parameter int unsigned ALMOST_EMPTY_LEVEL = 1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // 写侧
    input  logic                    wr_en,
    input  logic [WIDTH-1:0]        wrdata,

    // 读侧 (首字直通)
    input  logic                    rd_en,
    output logic [WIDTH-1:0]        rd_data,

    // 水位
    output logic                    full,
    output logic                    almost_full,
    output logic                    empty,
    output logic                    almost_empty
);

    localparam int unsigned PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned CNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    logic [WIDTH-1:0]       mem [DEPTH];
    logic [PTR_WIDTH-1:0]   wr_ptr;
    logic [PTR_WIDTH-1:0]   rd_ptr;
    logic [CNT_WIDTH-1:0]   cnt;

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    // 首字直通: 队头数据直接送到读数据口
    assign rd_data      = mem[rd_ptr];

    assign empty        = (cnt == '0);
    assign full         = (cnt == CNT_WIDTH'(DEPTH));
    assign almost_full  = (cnt >= CNT_WIDTH'(ALMOST_FULL_LEVEL));
    assign almost_empty = (cnt <= CNT_WIDTH'(ALMOST_EMPTY_LEVEL));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            cnt    <= '0;
        end
        else begin
            if (do_wr) begin
                mem[wr_ptr] <= wrdata;
                wr_ptr      <= (wr_ptr == PTR_WIDTH'(DEPTH - 1)) ? '0 : (wr_ptr + 1'b1);
            end

            if (do_rd) begin
                rd_ptr <= (rd_ptr == PTR_WIDTH'(DEPTH - 1)) ? '0 : (rd_ptr + 1'b1);
            end

            // 同拍又写又读时占用数不变
            case ({do_wr, do_rd})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire

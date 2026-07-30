module i2c_master #(parameter CLK_DIV = 4) (
    input  logic clk, rst_n, start, rw,
    input  logic [6:0] slave_addr,
    input  logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic busy, done, ack_error,
    inout  wire  sda,
    output logic scl
);
    typedef enum logic [2:0] {IDLE, START, SEND_ADDR, WAIT_ACK_ADDR,
                               WRITE_DATA, READ_DATA, WAIT_ACK_DATA, STOP} state_t;
    state_t state, next_state;

    logic sda_out, sda_oe;
    assign sda = sda_oe ? sda_out : 1'bz;

    logic [$clog2(CLK_DIV*2)-1:0] clk_cnt;
    logic scl_int, scl_prev;
    assign scl = scl_int;
    wire scl_rising  = scl_int & ~scl_prev;
    wire scl_falling = ~scl_int & scl_prev;

    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;
    logic rw_captured;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 0; scl_int <= 1; scl_prev <= 1;
        end else if (state == IDLE) begin
            clk_cnt <= 0; scl_int <= 1; scl_prev <= 1;
        end else begin
            scl_prev <= scl_int;
            if (clk_cnt == CLK_DIV-1) begin clk_cnt <= 0; scl_int <= ~scl_int; end
            else clk_cnt <= clk_cnt + 1;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:          if (start) next_state = START;
            START:         if (scl_falling) next_state = SEND_ADDR;
            SEND_ADDR:     if (scl_falling && bit_cnt==7) next_state = WAIT_ACK_ADDR;
            WAIT_ACK_ADDR: if (scl_rising) begin
                               if (rw_captured) next_state = READ_DATA;
                               else              next_state = WRITE_DATA;
                           end
            WRITE_DATA:    if (scl_falling && bit_cnt==7) next_state = WAIT_ACK_DATA;
            READ_DATA:     if (scl_falling && bit_cnt==7) next_state = WAIT_ACK_DATA;
            WAIT_ACK_DATA: if (scl_rising) next_state = STOP;
            STOP:          if (scl_falling) next_state = IDLE;
        endcase
    end
//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; bit_cnt<=0; shift_reg<=0; rw_captured<=0;
            data_out<=0; sda_out<=1; sda_oe<=0; busy<=0; done<=0; ack_error<=0;
        end else begin
            state <= next_state;
            done  <= 0;
            case (state)
                IDLE: begin
                    sda_oe<=0; sda_out<=1; busy<=0;
                    if (start) begin
                        busy<=1; shift_reg<={slave_addr,rw}; rw_captured<=rw;
                        bit_cnt<=0; ack_error<=0;
                    end
                end
                START: begin sda_oe<=1; sda_out<=0; end
                SEND_ADDR: begin
                    sda_oe<=1;
                    if (scl_falling) begin
                        sda_out<=shift_reg[7]; shift_reg<={shift_reg[6:0],1'b0};
                        bit_cnt<=bit_cnt+1;
                    end
                end
                WAIT_ACK_ADDR: begin
                    sda_oe<=0;
                    if (scl_rising) begin
                        ack_error<=sda; bit_cnt<=0;
                        if (!rw_captured) shift_reg<=data_in;
                    end
                end
                WRITE_DATA: begin
                    sda_oe<=1;
                    if (scl_falling) begin
                        sda_out<=shift_reg[7]; shift_reg<={shift_reg[6:0],1'b0};
                        bit_cnt<=bit_cnt+1;
                    end
                end
                READ_DATA: begin
                    sda_oe<=0;
                    if (scl_rising) begin
                        data_out<={data_out[6:0],sda}; bit_cnt<=bit_cnt+1;
                    end
                end
                WAIT_ACK_DATA: begin
                    if (!rw_captured) begin
                        sda_oe<=0;
                        if (scl_rising) ack_error<=sda;
                    end else begin
                        sda_oe<=1; sda_out<=1;
                    end
                end
                STOP: begin
                    sda_oe<=1; sda_out<=0;
                    if (scl_falling) sda_out<=1;
                    if (next_state==IDLE) begin done<=1; busy<=0; end
                end
            endcase
        end
    end
endmodule

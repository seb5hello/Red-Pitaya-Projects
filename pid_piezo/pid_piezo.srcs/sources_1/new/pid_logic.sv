`timescale 1ns / 1ps
 
module pid_logic  #(
    parameter DATA_WIDTH  = 32,
    parameter COEFF_WIDTH = 14,
    parameter OUT_WIDTH   = 14,
    parameter SHIFT_VAL   = 10,
    
    // Integrator limits remain static to prevent massive windup
    parameter signed MAX_INT = 32'sd500000,
    parameter signed MIN_INT = -32'sd500000
)(
    input  wire clk,
    input  wire rst_n,
    
    // 1-cycle strobe indicating new timestamp is ready
    input  wire data_valid_i, 
    
    // Pre-calculated error from the timestamp logic
    input  wire signed [DATA_WIDTH-1:0] error_i, 
    
    input  wire signed [COEFF_WIDTH-1:0] kp_i,
    input  wire signed [COEFF_WIDTH-1:0] ki_i,
    input  wire signed [COEFF_WIDTH-1:0] kd_i,
    
    // Dynamic output limits and baseline offset
    input  wire signed [OUT_WIDTH-1:0] offset_i,
    input  wire signed [OUT_WIDTH-1:0] max_out_i,
    input  wire signed [OUT_WIDTH-1:0] min_out_i,
    
    output reg  signed [OUT_WIDTH-1:0] dac_out_o,
    output reg  ready_o
);
    // --------------------------------------------------------
    // FSM States
    // --------------------------------------------------------
    localparam INIT    = 3'd6; // NEW: Initialization state
    localparam IDLE    = 3'd0;
    localparam CALC_P  = 3'd1;
    localparam CALC_I  = 3'd2;
    localparam CALC_D  = 3'd3;
    localparam ACCUM_I = 3'd4;
    localparam OUTPUT  = 3'd5;

    reg [2:0] state;

    // --------------------------------------------------------
    // Persistent State Registers
    // --------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] prev_error;
    reg signed [DATA_WIDTH-1:0] integrator;

    // --------------------------------------------------------
    // Shared Multiplier (Inferred as a single DSP block)
    // --------------------------------------------------------
    reg  signed [DATA_WIDTH-1:0]  mult_in_a;
    reg  signed [COEFF_WIDTH-1:0] mult_in_b;
    wire signed [DATA_WIDTH+COEFF_WIDTH-1:0] mult_out = mult_in_a * mult_in_b;
    
    // Explicitly shift and slice the multiplier output
    wire signed [DATA_WIDTH+COEFF_WIDTH-1:0] mult_out_shifted_raw = mult_out >>> SHIFT_VAL;
    wire signed [DATA_WIDTH-1:0] mult_out_shifted = mult_out_shifted_raw[DATA_WIDTH-1:0];

    // --------------------------------------------------------
    // Calculation Registers
    // --------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] term_p;
    reg signed [DATA_WIDTH-1:0] term_i;
    reg signed [DATA_WIDTH-1:0] term_d;
    
    // Padding constants for sign-extension to prevent WIDTHEXPAND warnings
    localparam PAD_SUM = 2; // Pad 32 bits to 34 bits
    localparam PAD_OUT = (DATA_WIDTH + 2) - OUT_WIDTH; // Pad OUT_WIDTH to 34 bits

    // --------------------------------------------------------
    // FSM Logic
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= INIT; // Start in INIT state upon coming out of reset
            prev_error <= 0;
            integrator <= 0;
            dac_out_o  <= 0;    // Hardware zero while reset is actively held low
            ready_o    <= 1'b0; // Not ready while resetting
            
            term_p <= 0;
            term_i <= 0;
            term_d <= 0;
            mult_in_a <= 0;
            mult_in_b <= 0;
        end else begin
            case (state)
                INIT: begin
                    // Safely clamp the initial offset before outputting
                    if (offset_i > max_out_i)
                        dac_out_o <= max_out_i;
                    else if (offset_i < min_out_i)
                        dac_out_o <= min_out_i;
                    else
                        dac_out_o <= offset_i;
                        
                    ready_o <= 1'b1;
                    state   <= IDLE;
                end

                IDLE: begin
                    ready_o <= 1'b1;
                    if (data_valid_i) begin
                        ready_o   <= 1'b0;
                        mult_in_a <= error_i;
                        mult_in_b <= kp_i;
                        state     <= CALC_P;
                    end
                end

                CALC_P: begin
                    term_p    <= mult_out_shifted;
                    mult_in_a <= error_i;
                    mult_in_b <= ki_i;
                    state     <= CALC_I;
                end

                CALC_I: begin
                    term_i    <= mult_out_shifted;
                    mult_in_a <= error_i - prev_error;
                    mult_in_b <= kd_i;
                    state     <= CALC_D;
                end

                CALC_D: begin
                    term_d     <= mult_out_shifted;
                    prev_error <= error_i;
                    state      <= ACCUM_I;
                end

                ACCUM_I: begin
                    // Explicitly extend to 33 bits to prevent overflow
                    automatic logic signed [DATA_WIDTH:0] ext_term_i     = {term_i[DATA_WIDTH-1], term_i};
                    automatic logic signed [DATA_WIDTH:0] ext_integrator = {integrator[DATA_WIDTH-1], integrator};
                    automatic logic signed [DATA_WIDTH:0] temp_int       = ext_integrator + ext_term_i;
                    
                    automatic logic signed [DATA_WIDTH:0] ext_max_int    = {MAX_INT[31], MAX_INT};
                    automatic logic signed [DATA_WIDTH:0] ext_min_int    = {MIN_INT[31], MIN_INT};
                    
                    if (temp_int > ext_max_int) 
                        integrator <= MAX_INT;
                    else if (temp_int < ext_min_int) 
                        integrator <= MIN_INT;
                    else 
                        integrator <= temp_int[DATA_WIDTH-1:0];
                        
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    // Explicitly extend PID terms to 34 bits
                    automatic logic signed [DATA_WIDTH+1:0] ext_p = { {PAD_SUM{term_p[DATA_WIDTH-1]}}, term_p };
                    automatic logic signed [DATA_WIDTH+1:0] ext_i = { {PAD_SUM{integrator[DATA_WIDTH-1]}}, integrator };
                    automatic logic signed [DATA_WIDTH+1:0] ext_d = { {PAD_SUM{term_d[DATA_WIDTH-1]}}, term_d };
                    
                    // Extend the dynamic offset input to 34 bits
                    automatic logic signed [DATA_WIDTH+1:0] ext_offset = { {PAD_OUT{offset_i[OUT_WIDTH-1]}}, offset_i };
                    
                    // Final sum includes the baseline offset
                    automatic logic signed [DATA_WIDTH+1:0] pid_sum = ext_p + ext_i + ext_d + ext_offset;

                    // Extend dynamic limits to 34 bits for safe comparison
                    automatic logic signed [DATA_WIDTH+1:0] ext_max_out = { {PAD_OUT{max_out_i[OUT_WIDTH-1]}}, max_out_i };
                    automatic logic signed [DATA_WIDTH+1:0] ext_min_out = { {PAD_OUT{min_out_i[OUT_WIDTH-1]}}, min_out_i };

                    if (pid_sum > ext_max_out) 
                        dac_out_o <= max_out_i;
                    else if (pid_sum < ext_min_out) 
                        dac_out_o <= min_out_i;
                    else 
                        dac_out_o <= pid_sum[OUT_WIDTH-1:0];
                        
                    state <= IDLE;
                end
                
                default: state <= INIT;
            endcase
        end
    end

endmodule
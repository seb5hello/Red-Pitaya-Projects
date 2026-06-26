`timescale 1ns / 1ps
 
module pid_logic  #(
    parameter DATA_WIDTH  = 32,
    parameter COEFF_WIDTH = 14,
    parameter OUT_WIDTH   = 14,
    parameter SHIFT_VAL   = 10,
    
    parameter signed MAX_INT = 32'sd500000,
    parameter signed MIN_INT = -32'sd500000,
    parameter signed MAX_OUT = 16'sd32767,
    parameter signed MIN_OUT = -16'sd32768
)(
    input  wire clk,
    input  wire rst_n,
    
    // 1-cycle strobe indicating tau_A and tau_B are ready
    // CRITICAL: Ensure this is driven by hardware, not software!
    input  wire data_valid_i, 
    
    // --- FIX: Separated inputs for Derivative on Measurement ---
    input  wire signed [DATA_WIDTH-1:0] setpoint_i, // Target timestamp
    input  wire signed [DATA_WIDTH-1:0] actual_i,   // Actual timestamp
    
    input  wire signed [COEFF_WIDTH-1:0] kp_i,
    input  wire signed [COEFF_WIDTH-1:0] ki_i,
    input  wire signed [COEFF_WIDTH-1:0] kd_i,
    
    output reg  signed [OUT_WIDTH-1:0] dac_out_o,
    output reg  ready_o
);

    // --------------------------------------------------------
    // FSM States
    // --------------------------------------------------------
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
    // --- FIX: Track actual value instead of error for D-term ---
    reg signed [DATA_WIDTH-1:0] prev_actual; 
    reg signed [DATA_WIDTH-1:0] integrator;

    // Calculate current error combinatorially
    wire signed [DATA_WIDTH-1:0] current_error = setpoint_i - actual_i;

    // --------------------------------------------------------
    // Shared Multiplier (Inferred as a single DSP block)
    // --------------------------------------------------------
    reg  signed [DATA_WIDTH-1:0]  mult_in_a;
    reg  signed [COEFF_WIDTH-1:0] mult_in_b;
    wire signed [DATA_WIDTH+COEFF_WIDTH-1:0] mult_out = mult_in_a * mult_in_b;
    
    // --- FIX: Rounding instead of pure truncation to prevent deadbands ---
    // Add 2^(SHIFT_VAL-1) before shifting right
    wire signed [DATA_WIDTH+COEFF_WIDTH-1:0] mult_out_rounded = mult_out + (1 << (SHIFT_VAL - 1));
    wire signed [DATA_WIDTH+COEFF_WIDTH-1:0] mult_out_shifted_raw = mult_out_rounded >>> SHIFT_VAL;
    wire signed [DATA_WIDTH-1:0] mult_out_shifted = mult_out_shifted_raw[DATA_WIDTH-1:0];

    // --------------------------------------------------------
    // Calculation Registers
    // --------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] term_p;
    reg signed [DATA_WIDTH-1:0] term_i;
    reg signed [DATA_WIDTH-1:0] term_d;
    
    localparam PAD_SUM = 2; 
    localparam PAD_OUT = (DATA_WIDTH + 2) - OUT_WIDTH; 

    // --------------------------------------------------------
    // FSM Logic
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            prev_actual <= 0;
            integrator  <= 0;
            dac_out_o   <= 0;
            ready_o     <= 1'b1;
            
            term_p <= 0;
            term_i <= 0;
            term_d <= 0;
            mult_in_a <= 0;
            mult_in_b <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready_o <= 1'b1;
                    if (data_valid_i) begin
                        ready_o   <= 1'b0;
                        mult_in_a <= current_error;
                        mult_in_b <= kp_i;
                        state     <= CALC_P;
                    end
                end

                CALC_P: begin
                    term_p    <= mult_out_shifted;
                    mult_in_a <= current_error;
                    mult_in_b <= ki_i;
                    state     <= CALC_I;
                end

                CALC_I: begin
                    term_i    <= mult_out_shifted;
                    // --- FIX: Derivative on Measurement ---
                    // -(actual_i - prev_actual) avoids kicks on setpoint changes
                    mult_in_a <= prev_actual - actual_i; 
                    mult_in_b <= kd_i;
                    state     <= CALC_D;
                end

                CALC_D: begin
                    term_d      <= mult_out_shifted;
                    prev_actual <= actual_i; // Save actual for next cycle
                    state       <= ACCUM_I;
                end

                ACCUM_I: begin
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
                    automatic logic signed [DATA_WIDTH+1:0] ext_p = { {PAD_SUM{term_p[DATA_WIDTH-1]}}, term_p };
                    automatic logic signed [DATA_WIDTH+1:0] ext_i = { {PAD_SUM{integrator[DATA_WIDTH-1]}}, integrator };
                    automatic logic signed [DATA_WIDTH+1:0] ext_d = { {PAD_SUM{term_d[DATA_WIDTH-1]}}, term_d };
                    
                    automatic logic signed [DATA_WIDTH+1:0] pid_sum = ext_p + ext_i + ext_d;
                    
                    automatic logic signed [DATA_WIDTH+1:0] ext_max_out = { {PAD_OUT{MAX_OUT[15]}}, MAX_OUT };
                    automatic logic signed [DATA_WIDTH+1:0] ext_min_out = { {PAD_OUT{MIN_OUT[15]}}, MIN_OUT };
                    
                    if (pid_sum > ext_max_out) 
                        dac_out_o <= MAX_OUT[OUT_WIDTH-1:0];
                    else if (pid_sum < ext_min_out) 
                        dac_out_o <= MIN_OUT[OUT_WIDTH-1:0];
                    else 
                        dac_out_o <= pid_sum[OUT_WIDTH-1:0];
                        
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
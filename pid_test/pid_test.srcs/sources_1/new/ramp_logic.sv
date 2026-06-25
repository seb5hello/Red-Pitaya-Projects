////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure Ramp Generator Logic (Soft Arm/Disarm Update)
////////////////////////////////////////////////////////////////////////////////
module ramp_logic (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Configuration Inputs (Driven by Bus Interface)
    input  logic [13:0]   min_val,
    input  logic [13:0]   max_val,
    input  logic [31:0]   period_val, 
    input  logic          continuous_en, 
    
    // Hardware Outputs
    output logic          trigger_out, 
    output logic [13:0]   dac_dat_o
);

    // Expanded State Machine
    localparam [2:0] IDLE      = 3'd0;
    localparam [2:0] ARMING    = 3'd1;
    localparam [2:0] READY     = 3'd2;
    localparam [2:0] RAMP_UP   = 3'd3;
    localparam [2:0] RAMP_DOWN = 3'd4;
    localparam [2:0] DISARMING = 3'd5;

    logic [2:0]  state;
    logic [31:0] acc;

    // -------------------------------------------------------------------------
    // PIPELINED CONFIGURATION
    // -------------------------------------------------------------------------
    logic [13:0] delta_v_comb;
    logic [13:0] min_val_reg;
    logic [13:0] delta_v_reg;

    // 1. Combinational Calculation
    // Unsigned 14-bit values are inherently >= 0. 
    // We just ensure max_val > min_val to avoid underflow in delta_v.
    assign delta_v_comb = (max_val > min_val) ? (max_val - min_val) : 14'd1;

    // 2. Register the results to break the timing path!
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            min_val_reg <= 14'd0;
            delta_v_reg <= 14'd1;
        end else begin
            min_val_reg <= min_val;
            delta_v_reg <= delta_v_comb;
        end
    end

    // -------------------------------------------------------------------------
    // RAMP LOGIC (State Machine)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            dac_dat_o   <= 14'd0;
            state       <= IDLE;
            trigger_out <= 1'b0;
            acc         <= 32'h0;
        end else begin
            trigger_out <= 1'b0; // Default trigger state

            case (state)
                IDLE: begin
                    dac_dat_o <= 14'd0;
                    if (arm_i) begin
                        state <= ARMING;
                    end
                end

                ARMING: begin
                    // Interruption: User disarmed while arming
                    if (~arm_i) begin
                        state <= DISARMING;
                    end else if (dac_dat_o >= min_val_reg) begin
                        dac_dat_o <= min_val_reg; // Cap exactly at min_val_reg
                        state     <= READY;
                    end else begin
                        dac_dat_o <= dac_dat_o + 14'd1;
                    end
                end

                READY: begin
                    if (~arm_i) begin
                        state <= DISARMING;
                    end else if (trigger_i) begin
                        state       <= RAMP_UP;
                        trigger_out <= 1'b1;
                        acc         <= 32'h0;
                    end
                end

                RAMP_UP: begin
                    if (~arm_i) begin
                        state <= DISARMING;
                    end else begin
                        if (acc + delta_v_reg >= period_val) begin
                            acc <= acc + delta_v_reg - period_val;
                            if (dac_dat_o >= max_val) begin
                                state       <= RAMP_DOWN;
                                dac_dat_o   <= dac_dat_o - 14'd1;
                                trigger_out <= 1'b1;
                            end else begin
                                dac_dat_o   <= dac_dat_o + 14'd1;
                            end
                        end else begin
                            acc <= acc + delta_v_reg;
                        end
                    end
                end

                RAMP_DOWN: begin
                    if (~arm_i) begin
                        state <= DISARMING;
                    end else begin
                        if (acc + delta_v_reg >= period_val) begin
                            acc <= acc + delta_v_reg - period_val;
                            
                            if (dac_dat_o <= min_val_reg) begin
                                // Check if we should loop or wait for next trigger
                                if (continuous_en) begin
                                    state       <= RAMP_UP;
                                    dac_dat_o   <= dac_dat_o + 14'd1;
                                    trigger_out <= 1'b1;
                                end else begin
                                    state     <= READY; // Returns to READY, not IDLE
                                    dac_dat_o <= min_val_reg;
                                end
                            end else begin
                                dac_dat_o   <= dac_dat_o - 14'd1;
                            end
                        end else begin
                            acc <= acc + delta_v_reg;
                        end
                    end
                end

                DISARMING: begin
                    // Interruption: User re-armed while disarming
                    if (arm_i) begin
                        state <= ARMING;
                    end else if (dac_dat_o == 14'd0) begin
                        state <= IDLE;
                    end else begin
                        dac_dat_o <= dac_dat_o - 14'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

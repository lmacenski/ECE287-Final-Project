// This code is a direct exerpt from our code used within the labs.
// This code is being used to display the current game score on the FPGA's 7 segment displays.
module three_decimal_vals_w_neg (
    input signed [7:0] val,
    output [6:0] seg7_dig0,
    output [6:0] seg7_dig1,
    output [6:0] seg7_dig2,
    output [6:0] seg7_neg_sign
);

    reg [7:0] abs_value;
    reg [3:0] digit0, digit1, digit2;
    reg is_negative;

    always @(*) begin
        is_negative = val[7];
        if (is_negative) begin
            abs_value = -val;
        end else begin
            abs_value = val;
        end

        digit0 = abs_value % 10;
        digit1 = (abs_value / 10) % 10;
        digit2 = (abs_value / 100) % 10;
    end

    seven_segment u0 (.digit(digit0), .seg(seg7_dig0));
    seven_segment u1 (.digit(digit1), .seg(seg7_dig1));
    seven_segment u2 (.digit(digit2), .seg(seg7_dig2));
    seven_segment_negative u3 (.is_neg(is_negative), .seg(seg7_neg_sign));

endmodule
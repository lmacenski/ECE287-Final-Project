// This code is a direct exerpt from our code used within the labs.
// This code is being used to display the current game score on the FPGA's 7 segment displays.
// This code shows the negative sign in front of the three digits when the score gets into the negatives.
module seven_segment_negative(
    input is_neg,
    output reg [6:0] seg
);

always @(*) begin
    if (is_neg)
        seg = 7'b0111111;
    else
        seg = 7'b1111111;
end

endmodule

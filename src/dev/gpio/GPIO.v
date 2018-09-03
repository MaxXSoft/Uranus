`timescale 1ns / 1ps

module  GPIO(
    input   wire        clk_timer,
    input   wire        clk     ,
    input   wire        rst     ,
    // read and write from CPU
    // ar
    input   wire[3 :0]  arid    ,
    input   wire[31:0]  araddr  ,
    input   wire[7 :0]  arlen   ,
    input   wire[2 :0]  arsize  ,
    input   wire[1 :0]  arburst ,
    input   wire[1 :0]  arlock  ,
    input   wire[3 :0]  arcache ,
    input   wire[2 :0]  arprot  ,
    input   wire        arvalid ,
    output  wire        arready ,
    //r
    output  wire[3 :0]  rid     ,
    output  wire[31:0]  rdata   ,
    output  wire[1 :0]  rresp   ,
    output  wire        rlast   ,
    output  wire        rvalid  ,
    input   wire        rready  ,
    //aw
    input   wire[3 :0]  awid    ,
    input   wire[31:0]  awaddr  ,
    input   wire[7 :0]  awlen   ,
    input   wire[2 :0]  awsize  ,
    input   wire[1 :0]  awburst ,
    input   wire[1 :0]  awlock  ,
    input   wire[3 :0]  awcache ,
    input   wire[2 :0]  awprot  ,
    input   wire        awvalid ,
    output  wire        awready ,
    //w
    input   wire[3 :0]  wid     ,
    input   wire[31:0]  wdata   ,
    input   wire[3 :0]  wstrb   ,
    input   wire        wlast   ,
    input   wire        wvalid  ,
    output  wire        wready  ,
    //b
    output  wire[3 :0]  bid     ,
    output  wire[1 :0]  bresp   ,
    output  wire        bvalid  ,
    input   wire        bready  ,
    // GPIO control
    input   wire[7 :0]  switch  ,
    input   wire[15:0]  keypad  ,
    output  reg [1 :0]  bicolor_led_0,
    output  reg [1 :0]  bicolor_led_1,
    output  reg [15:0]  led     ,
    output  reg [31:0]  num
);

//--------------------------{axi interface}begin-------------------------//
    reg busy,write,R_or_W;

    wire    ar_enter    = arvalid & arready;
    wire    r_retire    = rvalid  & rready & rlast;
    wire    aw_enter    = awvalid & awready;
    wire    w_enter     = wvalid  & wready & wlast;
    wire    b_retire    = bvalid  & bready;

    assign  arready     = ~busy & (!R_or_W | !awvalid);
    assign  awready     = ~busy & ( R_or_W | !arvalid);

    reg [3 :0]  buf_id;
    reg [31:0]  buf_addr;
    reg [7 :0]  buf_len;
    reg [2 :0]  buf_size;

    always @ (posedge clk)  begin
        if (!rst)   busy    <= 1'b0;
        else if (ar_enter | aw_enter)   busy    <= 1'b1;
        else if (r_retire | b_retire)   busy    <= 1'b0;
    end

    always @ (posedge clk)  begin
        if (!rst)   begin
            R_or_W      <= 1'b0;
            buf_id      <= 4'b0;
            buf_addr    <= 31'h0;
            buf_len     <= 8'b0;
            buf_size    <= 3'b0;
        end else if (ar_enter | aw_enter)   begin
            R_or_W      <= ar_enter;
            buf_id      <= ar_enter ? arid   : awid   ;
            buf_addr    <= ar_enter ? araddr : awaddr ;
            buf_len     <= ar_enter ? arlen  : awlen  ;
            buf_size    <= ar_enter ? arsize : awsize ;
        end
    end

    reg wready_reg;
    assign  wready  = wready_reg;
    always @ (posedge clk)  begin
        if      (!rst           )   wready_reg  <= 1'b0;
        else if (aw_enter       )   wready_reg  <= 1'b1;
        else if (w_enter & wlast)   wready_reg  <= 1'b0;
    end

    reg rvalid_reg;
    reg rlast_reg;
    assign  rvalid  = rvalid_reg;
    assign  rlast   = rlast_reg;
    always @ (posedge clk)  begin
        if (!rst)   begin
           rvalid_reg   <= 1'b0;
           rlast_reg    <= 1'b0;
        end
        else if (busy & R_or_W & !r_retire)     begin
            rvalid_reg  <= 1'b1;
            rlast_reg   <= 1'b1;
        end
        else if (r_retire)  begin
            rvalid_reg  <= 1'b0;
        end
    end

    reg [31:0]  data_out;
    assign  rdata   = data_out;

    reg bvalid_reg;
    assign  bvalid  = bvalid_reg;
    always @ (posedge clk)  begin
        if      (!rst    )  bvalid_reg  <= 1'b0;
        else if (w_enter )  bvalid_reg  <= 1'b1;
        else if (b_retire)  bvalid_reg  <= 1'b0;
    end

    assign  rid     = buf_id;
    assign  bid     = buf_id;
    assign  bresp   = 2'b0;
    assign  rresp   = 2'b0;

//---------------------------{axi interface}end--------------------------//

    // flags
    wire read_flag  = ar_enter;
    wire write_flag = aw_enter;

    wire[31:0]  addr    = read_flag ? araddr : write_flag ? awaddr : 32'h0;
    wire[31:0]  data_in = wdata;

    // address definition
    wire[11:0] address = addr[11:0];
    parameter kSwitchAddr = 12'h000, kKeypadAddr = 12'h004,
            kBicolor0Addr = 12'h008, kBicolor1Addr = 12'h00c,
            kLEDAddr = 12'h010, kNumAddr = 12'h014,
            kTimerAddr = 12'h018;

    // timer
    reg[31:0] timer, timer_write_flag;
    wire[31:0] next_timer = timer + 1;
    always @(posedge clk_timer) begin
        if (!rst) begin
            timer <= 0;
            timer_write_flag <= 0;
        end
        else if (!timer_write_flag) begin
            if (write_flag && address == kTimerAddr) begin
                timer <= data_in;
                timer_write_flag <= 1;
            end
            else begin
                timer <= next_timer;
            end
        end
        else if (!write_flag) begin
            timer <= next_timer;
            timer_write_flag <= 0;
        end
        else begin
            timer <= next_timer;
        end
    end

    // read
    always @(posedge clk) begin
        if (!rst) begin
            data_out <= 0;
        end
        else if (read_flag) begin
            case (address)
                kSwitchAddr: data_out <= {24'h0, switch};
                kKeypadAddr: data_out <= {16'h0, keypad};
                kBicolor0Addr: data_out <= {30'h0, bicolor_led_0};
                kBicolor1Addr: data_out <= {30'h0, bicolor_led_1};
                kLEDAddr: data_out <= {16'h0, led};
                kNumAddr: data_out <= num;
                kTimerAddr: data_out <= timer;
            endcase
        end
    end

    // write
    always @(posedge clk) begin
        if (!rst) begin
            bicolor_led_0 <= 2'h0;
            bicolor_led_1 <= 2'h0;
            led <= 16'hffff;
            num <= 32'h0;
        end
        else if (write_flag) begin
            case (address)
                kBicolor0Addr: bicolor_led_0 <= data_in[1:0];
                kBicolor1Addr: bicolor_led_1 <= data_in[1:0];
                kLEDAddr: led <= data_in[15:0];
                kNumAddr: num <= data_in;
                default:;
            endcase
        end
    end

endmodule

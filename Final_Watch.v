`timescale 1ns / 1ps

module Final_Watch(
    input clk,               // 50MHz(추후 직접 해보고 조정을 하는 걸로,,,)
    input rst_sw,           
    input [7:1] dip_sw,      
    input [11:0] key_pad,    

    output [7:0] seg_data,
    output [7:0] seg_com,

    output [7:0] lcd_data,
    output lcd_rs, lcd_rw, lcd_e,


    output reg [3:0] led_r,
    output reg [3:0] led_g,
    output reg [3:0] led_b,

    output piezo
);

    wire rst = rst_sw;

    
    wire [11:0] btn;
    oneshot_universal #(.WIDTH(12)) u_key(
        .clk(clk),
        .rst(rst),
        .btn(key_pad),
        .btn_trig(btn)
    );


    reg view_24h_mode;  // 1: 24H, 0: 12H (표시용)

    always @(posedge clk or negedge rst) begin
        if(!rst) 
            view_24h_mode <= 1; // 기본 24시 모드
        else if((dip_sw[1] | dip_sw[2] | dip_sw[3] | dip_sw[4]) && btn[10]) // key 0
            view_24h_mode <= ~view_24h_mode;
    end

    reg [25:0] cnt_1s; 
    reg tick_1hz;
    always @(posedge clk or negedge rst) begin
        if(!rst) begin 
            cnt_1s   <= 0; 
            tick_1hz <= 0; 
        end
        else if(cnt_1s == 26'd49_999_999) begin
            cnt_1s   <= 0; 
            tick_1hz <= 1; 
        end
        else begin
            cnt_1s   <= cnt_1s + 1; 
            tick_1hz <= 0; 
        end
    end

    // 1kHz (반응속도 측정용)
    reg [15:0] cnt_1ms; 
    reg tick_1khz;
    always @(posedge clk or negedge rst) begin
        if(!rst) begin 
            cnt_1ms   <= 0; 
            tick_1khz <= 0; 
        end
        else if(cnt_1ms == 16'd49_999) begin
            cnt_1ms   <= 0; 
            tick_1khz <= 1; 
        end
        else begin
            cnt_1ms   <= cnt_1ms + 1; 
            tick_1khz <= 0; 
        end
    end

    // LCD용 느린 클럭 (음...대충 수백 Hz 수준 일단 이렇게 해보고 실험실에서 보면서 조절하는 걸로 해야할 듯ㅇㅇ)
    reg [16:0] cnt_lcd; 
    reg lcd_clk;
    always @(posedge clk or negedge rst) begin
        if(!rst) begin 
            cnt_lcd <= 0; 
            lcd_clk <= 0; 
        end
        else begin
            cnt_lcd <= cnt_lcd + 1;
            lcd_clk <= cnt_lcd[16];
        end
    end


    wire [3:0] c_h10, c_h1, c_m10, c_m1, c_s10, c_s1;
    wire [127:0] lcd_clk_1, lcd_clk_2;

    Mode_Clock u_clock(
        .clk(clk),
        .rst(rst),
        .tick_1hz(tick_1hz),
        .btn(btn),
        .dip_sw(dip_sw[7:1]),
        .view_24h(view_24h_mode),
        .cur_h10(c_h10), .cur_h1(c_h1),
        .cur_m10(c_m10), .cur_m1(c_m1),
        .cur_s10(c_s10), .cur_s1(c_s1),
        .lcd_l1(lcd_clk_1),
        .lcd_l2(lcd_clk_2)
    );

    wire ring_alm;
    wire [127:0] lcd_alm_1, lcd_alm_2;
    Mode_Alarm u_alarm(
        .clk(clk),
        .rst(rst),
        .btn(btn),
        .dip_sw(dip_sw[7:1]),
        .cur_h10(c_h10), .cur_h1(c_h1),
        .cur_m10(c_m10), .cur_m1(c_m1),
        .cur_s10(c_s10), .cur_s1(c_s1),
        .alarm_ring(ring_alm),
        .lcd_l1(lcd_alm_1),
        .lcd_l2(lcd_alm_2)
    );

    wire ring_tmr;
    wire [23:0] seg_tmr;
    wire [127:0] lcd_tmr_1, lcd_tmr_2;
    Mode_Timer u_timer(
        .clk(clk),
        .rst(rst),
        .tick_1hz(tick_1hz),
        .btn(btn),
        .dip_sw(dip_sw[7:1]),
        .timer_ring(ring_tmr),
        .timer_seg_data(seg_tmr),
        .lcd_l1(lcd_tmr_1),
        .lcd_l2(lcd_tmr_2)
    );

    wire [23:0] seg_game;
    wire [127:0] lcd_game_1, lcd_game_2;
    wire [3:0] game_r, game_g, game_b;

    Mode_Game u_game(
        .clk(clk),
        .rst(rst),
        .tick_1khz(tick_1khz),
        .btn(btn),
        .dip_sw(dip_sw[7:1]),
        .led_r(game_r),
        .led_g(game_g),
        .led_b(game_b),
        .game_seg_data(seg_game),
        .lcd_l1(lcd_game_1),
        .lcd_l2(lcd_game_2)
    );

    reg [4:0] base_hour_24;
    reg [4:0] off_h;
    reg [4:0] city_hour_24;

    always @(*) begin
        // Seoul 현재 시간(24H) 기준
        base_hour_24 = (c_h10 * 5'd10) + c_h1;

        // 도시 선택 (NY, London, Paris)
        if(dip_sw[2])       off_h = 5'd10; 
        else if(dip_sw[3])  off_h = 5'd15; 
        else if(dip_sw[4])  off_h = 5'd16; 
        else                off_h = 5'd0;  

        city_hour_24 = base_hour_24 + off_h;
        if(city_hour_24 >= 5'd24)
            city_hour_24 = city_hour_24 - 5'd24;
    end


    reg [3:0] city_h10_24, city_h1_24;
    always @(*) begin
        if(city_hour_24 >= 5'd20) begin
            city_h10_24 = 4'd2;
            city_h1_24  = city_hour_24 - 5'd20;
        end
        else if(city_hour_24 >= 5'd10) begin
            city_h10_24 = 4'd1;
            city_h1_24  = city_hour_24 - 5'd10;
        end
        else begin
            city_h10_24 = 4'd0;
            city_h1_24  = city_hour_24[3:0];
        end
    end

    // 12H 변환 후 표시용 시간
    reg [3:0] disp_h10, disp_h1;
    always @(*) begin
        if(view_24h_mode) begin
            // 24H 그대로 표시
            disp_h10 = city_h10_24;
            disp_h1  = city_h1_24;
        end
        else begin
            // 12H 변환
            if(city_h10_24 == 0 && city_h1_24 == 0) begin
                // 0시 -> 12시
                disp_h10 = 4'd1;
                disp_h1  = 4'd2;
            end
            else if(city_h10_24 == 1 && city_h1_24 > 4'd2) begin
                disp_h10 = 4'd0;
                disp_h1  = city_h1_24 - 4'd2;
            end
            else if(city_h10_24 == 2) begin
                disp_h10 = (city_h1_24 >= 4'd2) ? 4'd1 : 4'd0;
                if(city_h1_24 == 4'd0)      disp_h1 = 4'd8; 
                else if(city_h1_24 == 4'd1) disp_h1 = 4'd9; 
                else                        disp_h1 = city_h1_24 - 4'd2; 
            end
            else begin
                disp_h10 = city_h10_24;
                disp_h1  = city_h1_24;
            end
        end
    end

    reg [23:0] final_seg;
    reg [5:0]  final_dots;
    reg [127:0] final_l1, final_l2;
    reg final_piezo;

    always @(*) begin
        // 기본: 시계 / 세계시 출력
        final_seg   = {disp_h10, disp_h1, c_m10, c_m1, c_s10, c_s1};
        final_dots  = 6'b010100; 
        final_l1    = lcd_clk_1;
        final_l2    = lcd_clk_2;
        final_piezo = ring_alm; 

        led_r = 0;
        led_g = 0;
        led_b = 0;

        if(dip_sw[7]) begin
            final_seg   = seg_game;
            final_l1    = lcd_game_1;
            final_l2    = lcd_game_2;
            final_dots  = 6'b000000;

            led_r = game_r;
            led_g = game_g;
            led_b = game_b;

            final_piezo = 1'b0; 
        end
        else if(dip_sw[6]) begin
            final_seg   = seg_tmr;
            final_l1    = lcd_tmr_1;
            final_l2    = lcd_tmr_2;
            final_piezo = ring_tmr;
        end
        else if(dip_sw[5]) begin
            final_seg = {c_h10, c_h1, c_m10, c_m1, c_s10, c_s1};
            final_l1  = lcd_alm_1;
            final_l2  = lcd_alm_2;
        end
    end

    Piezo_Driver u_piezo(
        .clk(clk),
        .rst(rst),
        .en(final_piezo),
        .piezo_out(piezo)
    );

    Seven_Seg_Driver u_seg(
        .clk(clk),
        .rst(rst),
        .disp_data(final_seg),
        .dots(final_dots),
        .seg_data(seg_data),
        .seg_com(seg_com)
    );

    Text_LCD_Driver u_lcd(
        .clk(lcd_clk),
        .rst(rst),
        .line1_data(final_l1),
        .line2_data(final_l2),
        .LCD_E(lcd_e),
        .LCD_RS(lcd_rs),
        .LCD_RW(lcd_rw),
        .LCD_DATA(lcd_data)
    );

endmodule

module oneshot_universal(
    input clk,
    input rst,
    input  [WIDTH-1:0] btn,
    output reg [WIDTH-1:0] btn_trig
);
    parameter WIDTH = 1;

    reg [WIDTH-1:0] btn_reg;
    
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            btn_reg   <= {WIDTH{1'b0}};
            btn_trig  <= {WIDTH{1'b0}};
        end
        else begin
            btn_reg  <= btn;
            btn_trig <= btn & ~btn_reg; 
        end
    end
endmodule

module Mode_Clock(
    input clk, rst,
    input tick_1hz,
    input [11:0] btn,
    input [7:1] dip_sw,
    input view_24h,

    output reg [3:0] cur_h10, cur_h1,
    output reg [3:0] cur_m10, cur_m1,
    output reg [3:0] cur_s10, cur_s1,

    output reg [127:0] lcd_l1,
    output reg [127:0] lcd_l2
);
    localparam KEY_1    = 0;
    localparam KEY_2    = 1;
    localparam KEY_3    = 2;
    localparam KEY_STAR = 9;
    localparam KEY_SHARP= 11;

    reg [1:0] state;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            {cur_h10, cur_h1, cur_m10, cur_m1, cur_s10, cur_s1} <= 24'h12_00_00; 
        end 
        else begin
            if(tick_1hz) begin
                if(cur_s1 == 9) begin
                    cur_s1 <= 0;
                    if(cur_s10 == 5) begin
                        cur_s10 <= 0;
                        if(cur_m1 == 9) begin
                            cur_m1 <= 0;
                            if(cur_m10 == 5) begin
                                cur_m10 <= 0;
                                if(cur_h10==2 && cur_h1==3) begin
                                    cur_h10 <= 0; 
                                    cur_h1  <= 0;
                                end
                                else if(cur_h1==9) begin
                                    cur_h1  <= 0;
                                    cur_h10 <= cur_h10 + 1;
                                end
                                else cur_h1 <= cur_h1 + 1;
                            end
                            else cur_m10 <= cur_m10 + 1;
                        end
                        else cur_m1 <= cur_m1 + 1;
                    end
                    else cur_s10 <= cur_s10 + 1;
                end
                else cur_s1 <= cur_s1 + 1;
            end

            if(dip_sw[1]) begin
                case(state)
                    2'd1: begin 
                        if(btn[KEY_3]) begin
                            if(cur_h10==2 && cur_h1==3) begin 
                                cur_h10<=0; cur_h1<=0; 
                            end
                            else if(cur_h1==9) begin 
                                cur_h1<=0; cur_h10<=cur_h10+1; 
                            end
                            else cur_h1<=cur_h1+1;
                        end
                        if(btn[KEY_1]) begin
                            if(cur_h10==0 && cur_h1==0) begin 
                                cur_h10<=2; cur_h1<=3; 
                            end
                            else if(cur_h1==0) begin 
                                cur_h1<=9; cur_h10<=cur_h10-1; 
                            end
                            else cur_h1<=cur_h1-1;
                        end
                    end

                    2'd2: begin // M 설정
                        if(btn[KEY_3]) begin
                            if(cur_m1==9) begin
                                cur_m1<=0;
                                if(cur_m10==5) cur_m10<=0;
                                else           cur_m10<=cur_m10+1;
                            end 
                            else cur_m1<=cur_m1+1;
                        end
                        if(btn[KEY_1]) begin
                            if(cur_m10==0 && cur_m1==0) begin 
                                cur_m10<=5; cur_m1<=9; 
                            end
                            else if(cur_m1==0) begin 
                                cur_m1<=9;
                                if(cur_m10==0) cur_m10<=5;
                                else           cur_m10<=cur_m10-1;
                            end
                            else cur_m1<=cur_m1-1;
                        end
                    end

                    2'd3: begin // S 초기화
                        if(btn[KEY_2]) begin 
                            cur_s10<=0; cur_s1<=0; 
                        end
                    end
                endcase
            end
        end
    end


    always @(posedge clk or negedge rst) begin
        if(!rst) 
            state <= 0;
        else if(dip_sw[1]) begin
            if(btn[KEY_STAR])      state <= (state==0)?3:state-1;
            else if(btn[KEY_SHARP])state <= (state==3)?0:state+1;
        end
        else 
            state <= 0;
    end

    always @(*) begin
        if(dip_sw[1]) begin
            lcd_l1 = "     Seoul      ";
            case(state)
                0: lcd_l2 = view_24h ? "    Mode:24H    " : "    Mode:12H    ";
                1: lcd_l2 = "   Adjust Hour  ";
                2: lcd_l2 = "   Adjust Min   ";
                3: lcd_l2 = "    Reset Sec   ";
            endcase
        end
        else if(dip_sw[2]) begin 
            lcd_l1="    New York    "; 
            lcd_l2 = view_24h ? "    Mode:24H    " : "    Mode:12H    ";
        end
        else if(dip_sw[3]) begin 
            lcd_l1="     London     "; 
            lcd_l2 = view_24h ? "    Mode:24H    " : "    Mode:12H    ";
        end
        else if(dip_sw[4]) begin 
            lcd_l1="     Paris      "; 
            lcd_l2 = view_24h ? "    Mode:24H    " : "    Mode:12H    "; 
        end
        else begin
            lcd_l1="                "; 
            lcd_l2="                "; 
        end
    end
endmodule


module Mode_Alarm(
    input clk, rst,
    input [11:0] btn,
    input [7:1] dip_sw,

    input [3:0] cur_h10, cur_h1,
    input [3:0] cur_m10, cur_m1,
    input [3:0] cur_s10, cur_s1,

    output alarm_ring,
    output reg [127:0] lcd_l1,
    output reg [127:0] lcd_l2
);
    localparam KEY_1    = 0;
    localparam KEY_2    = 1;
    localparam KEY_3    = 2;
    localparam KEY_STAR = 9;
    localparam KEY_0    = 10;
    localparam KEY_SHARP= 11;

    reg [2:0] state;

    reg [3:0] al_h10, al_h1, al_m10, al_m1, al_s10, al_s1;
    reg is_ringing;
    reg alarm_set; 

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            state <= 0;
            {al_h10,al_h1,al_m10,al_m1,al_s10,al_s1} <= 0;
            is_ringing <= 0;
            alarm_set  <= 0;
        end 
        else begin
            if(is_ringing && btn[KEY_0]) 
                is_ringing <= 0;
                
               
            if(state == 3'd4) begin
                if({cur_h10,cur_h1,cur_m10,cur_m1,cur_s10,cur_s1} ==
                   {al_h10,al_h1,al_m10,al_m1,al_s10,al_s1})
                    is_ringing <= 1;
            end

            if(dip_sw[5]) begin
                if(btn[KEY_STAR])       state <= (state==0)?4:state-1;
                else if(btn[KEY_SHARP]) state <= (state==4)?0:state+1;

                
                if(state==0 && btn[KEY_2]) begin
                    {al_h10,al_h1,al_m10,al_m1,al_s10,al_s1} <= 0;
                    alarm_set  <= 0;
                    is_ringing <= 0;
                end

                // H 설정
                if(state==1) begin
                    if(btn[KEY_3]) begin
                        alarm_set <= 1;
                        if(al_h10==2 && al_h1==3) begin 
                            al_h10<=0; al_h1<=0; 
                        end
                        else if(al_h1==9) begin 
                            al_h1<=0; al_h10<=al_h10+1; 
                        end
                        else al_h1<=al_h1+1;
                    end
                    if(btn[KEY_1]) begin
                        alarm_set <= 1;
                        if(al_h10==0 && al_h1==0) begin 
                            al_h10<=2; al_h1<=3; 
                        end
                        else if(al_h1==0) begin 
                            al_h1<=9; al_h10<=al_h10-1; 
                        end
                        else al_h1<=al_h1-1;
                    end
                end
                // M 설정
                else if(state==2) begin
                    if(btn[KEY_3]) begin
                        alarm_set <= 1;
                        if(al_m1==9) begin 
                            al_m1<=0; 
                            al_m10 <= (al_m10==5)?0:al_m10+1; 
                        end
                        else al_m1<=al_m1+1;
                    end
                    if(btn[KEY_1]) begin
                        alarm_set <= 1;
                        if(al_m10==0 && al_m1==0) begin 
                            al_m10<=5; al_m1<=9; 
                        end
                        else if(al_m1==0) begin 
                            al_m1<=9; 
                            al_m10 <= (al_m10==0)?5:al_m10-1; 
                        end
                        else al_m1<=al_m1-1;
                    end
                end
                // S 설정 (초 초기화만)
                else if(state==3) begin
                    if(btn[KEY_3]) begin
                        alarm_set <= 1;
                        if(al_s1==9) begin 
                            al_s1  <= 0; 
                            al_s10 <= (al_s10==5)? 0 : al_s10+1; 
                        end
                        else al_s1 <= al_s1+1;
                    end
                
                    if(btn[KEY_1]) begin
                        alarm_set <= 1;
                        if(al_s10==0 && al_s1==0) begin 
                            al_s10 <= 5; 
                            al_s1  <= 9; 
                        end
                        else if(al_s1==0) begin 
                            al_s1  <= 9; 
                            al_s10 <= (al_s10==0)? 5 : al_s10-1; 
                        end
                        else al_s1 <= al_s1-1;
                    end
                
                    if(btn[KEY_2]) begin 
                        alarm_set <= 1;
                        al_s10 <= 0; 
                        al_s1  <= 0; 
                    end
                end
            end
        end
    end

    assign alarm_ring = is_ringing;

    always @(*) begin
        lcd_l1 = "   Alarm Mode   ";

        if(state==0) begin
            if(!alarm_set)
                lcd_l2 = "Alarm:Non       ";
            else
                lcd_l2 = "Alarm:OFF       ";
        end
        else if(state==1) begin
            lcd_l2 = {"Set H ",
                (8'd48 + al_h10), (8'd48 + al_h1), ":",
                (8'd48 + al_m10), (8'd48 + al_m1), ":",
                (8'd48 + al_s10), (8'd48 + al_s1),
                "  "
            };
        end
        
        else if(state==2) begin
            lcd_l2 = {
                    "Set M ",
                    (8'd48 + al_h10), (8'd48 + al_h1), ":",
                    (8'd48 + al_m10), (8'd48 + al_m1), ":",
                    (8'd48 + al_s10), (8'd48 + al_s1),
                    "  "
                };
        end
        else if(state==3) begin
            lcd_l2 = {
                    "Set S ",
                    (8'd48 + al_h10), (8'd48 + al_h1), ":",
                    (8'd48 + al_m10), (8'd48 + al_m1), ":",
                    (8'd48 + al_s10), (8'd48 + al_s1),
                    "  "
                };
        end
        else begin
            if(is_ringing)
                lcd_l2 = "Alarm Ringing!! ";  
            else
                lcd_l2 = {
                    "Alarm ",
                    (8'd48 + al_h10), (8'd48 + al_h1), ":",
                    (8'd48 + al_m10), (8'd48 + al_m1), ":",
                    (8'd48 + al_s10), (8'd48 + al_s1),
                    "  "
                };
        end

    end
endmodule


module Mode_Timer(
    input clk, rst, tick_1hz,
    input [11:0] btn,
    input [7:1] dip_sw,

    output timer_ring,
    output reg [23:0] timer_seg_data,
    output reg [127:0] lcd_l1, lcd_l2
);
    localparam KEY_1    = 0;
    localparam KEY_3    = 2;
    localparam KEY_STAR = 9;
    localparam KEY_0    = 10;
    localparam KEY_SHARP= 11;

    reg [3:0] tm_m10, tm_m1, tm_s10, tm_s1;
    reg [1:0] state;   
    reg is_run, is_end;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            state <= 0; 
            is_run <= 0; 
            is_end <= 0;
            {tm_m10,tm_m1,tm_s10,tm_s1} <= 0;
        end 
        else begin
            if(is_run && tick_1hz) begin
                if(tm_s1==0) begin
                    if(tm_s10==0) begin
                        if(tm_m1==0) begin
                            if(tm_m10==0) begin 
                                is_run <= 0; 
                                is_end <= 1;  // 끝
                            end 
                            else begin 
                                tm_m10 <= tm_m10-1; 
                                tm_m1  <= 9; 
                                tm_s10 <= 5; 
                                tm_s1  <= 9; 
                            end
                        end 
                        else begin 
                            tm_m1  <= tm_m1-1; 
                            tm_s10 <= 5; 
                            tm_s1  <= 9; 
                        end
                    end 
                    else begin 
                        tm_s10 <= tm_s10-1; 
                        tm_s1  <= 9; 
                    end
                end 
                else tm_s1 <= tm_s1-1;
            end

            if(dip_sw[6]) begin
                // 모드 이동
                if(btn[KEY_STAR])      state <= (state==0)?3:state-1;
                else if(btn[KEY_SHARP])state <= (state==3)?0:state+1;

              
                if(state==2'd3 && btn[KEY_0]) begin
                    if(is_end) begin 
                        is_end <= 0; 
                        state  <= 0;  // 비활성 모드로
                    end
                    else 
                        is_run <= ~is_run;
                end

                // 분 설정
                if(state==2'd1) begin
                    if(btn[KEY_3]) begin
                        if(tm_m1==9) begin 
                            tm_m1 <= 0; 
                            tm_m10 <= (tm_m10==5)?0:tm_m10+1; 
                        end
                        else tm_m1 <= tm_m1+1;
                    end
                    if(btn[KEY_1]) begin
                        if(tm_m10==0 && tm_m1==0) begin 
                            tm_m10<=5; tm_m1<=9; 
                        end
                        else if(tm_m1==0) begin 
                            tm_m1<=9; 
                            tm_m10 <= (tm_m10==0)?5:tm_m10-1; 
                        end
                        else tm_m1<=tm_m1-1;
                    end
                end

                // 초 설정
                if(state==2'd2) begin
                    if(btn[KEY_3]) begin
                        if(tm_s1==9) begin 
                            tm_s1<=0; 
                            tm_s10 <= (tm_s10==5)?0:tm_s10+1; 
                        end
                        else tm_s1<=tm_s1+1;
                    end
                    if(btn[KEY_1]) begin
                        if(tm_s10==0 && tm_s1==0) begin 
                            tm_s10<=5; tm_s1<=9; 
                        end
                        else if(tm_s1==0) begin 
                            tm_s1<=9; 
                            tm_s10 <= (tm_s10==0)?5:tm_s10-1; 
                        end
                        else tm_s1<=tm_s1-1;
                    end
                end

                // 비활성(Reset) 모드에서는 완전 초기화
                if(state==2'd0) begin
                    {tm_m10,tm_m1,tm_s10,tm_s1} <= 0;
                    is_run <= 0;
                    is_end <= 0;
                end
            end
        end
    end

    assign timer_ring = is_end;

    always @(*) begin
        timer_seg_data = {4'h0,4'h0, tm_m10,tm_m1,tm_s10,tm_s1};
        lcd_l1 = "   Timer Mode   ";
        case(state)
            2'd0: lcd_l2 = "   Reset Mode   ";  
            2'd1: lcd_l2 = "   Set Minute   ";
            2'd2: lcd_l2 = "   Set Second   ";
            2'd3: begin
                if(is_end)      lcd_l2 = "   Time OVER!!! ";
                else if(is_run) lcd_l2 = "   Running...   ";
                else            lcd_l2 = "   Pause/Ready  ";
            end
        endcase
    end
endmodule

module Mode_Game(
    input clk, rst, tick_1khz,
    input [11:0] btn,
    input [7:1] dip_sw,

    output reg [3:0] led_r,
    output reg [3:0] led_g,
    output reg [3:0] led_b,

    output reg [23:0] game_seg_data,
    output reg [127:0] lcd_l1, lcd_l2
);
    localparam KEY_0 = 10;

    reg [1:0] g_state; 
    reg [15:0] ms_cnt;        
    reg [15:0] result_ms;    
    reg [15:0] wait_timer;    

    
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            g_state    <= 0; 
            ms_cnt     <= 0; 
            wait_timer <= 0;
            result_ms  <= 16'hFFFF;
            led_r <= 0; 
            led_g <= 0; 
            led_b <= 0;
        end 
        else if(dip_sw[7]) begin
            case(g_state)
                2'd0: begin
                    led_r <= 0; led_g <= 0; led_b <= 0;
                    ms_cnt     <= 0;
                    wait_timer <= 0;
                    result_ms  <= 16'hFFFF; 
                    if(btn[KEY_0]) begin
                        g_state    <= 1;
                        wait_timer <= 0;
                    end
                end

                2'd1: begin
                    led_r <= 0; 
                    led_g <= 0; 
                    led_b <= 4'hF; 
                    if(btn[KEY_0]) begin
                        g_state   <= 3;
                        result_ms <= 16'hFFFF; 
                        led_r <= 4'hF; led_g <= 0; led_b <= 0; 
                    end
                    else if(tick_1khz) begin
                        if(wait_timer >= 16'd3000) begin
                            g_state <= 2; 
                            ms_cnt  <= 0;
                        end
                        else 
                            wait_timer <= wait_timer + 1;
                    end
                end

                2'd2: begin
                    led_r <= 0; 
                    led_g <= 4'hF; 
                    led_b <= 0; 
                    if(btn[KEY_0]) begin
                        g_state   <= 3;
                        result_ms <= ms_cnt; 
                        led_r <= 4'hF; led_g <= 4'hF; led_b <= 4'hF; 
                    end
                    else if(tick_1khz) begin
                        if(ms_cnt < 16'd9999) 
                            ms_cnt <= ms_cnt + 1;
                    end
                end

                2'd3: begin
                    if(btn[KEY_0]) begin
                        g_state <= 0;
                    end
                end
            endcase
        end
    end

    
    reg [3:0] ms_th, ms_h, ms_t, ms_o; 
    integer tmp;

    always @(*) begin
        lcd_l1 = "  Reaction Test ";

        if(result_ms == 16'hFFFF) begin
            game_seg_data = 24'hEEEEEE;
        end
        else begin
            tmp  = result_ms;
            ms_th = tmp / 1000;
            tmp   = tmp % 1000;
            ms_h  = tmp / 100;
            tmp   = tmp % 100;
            ms_t  = tmp / 10;
            ms_o  = tmp % 10;

            
            game_seg_data = {4'h0, 4'h0, ms_th, ms_h, ms_t, ms_o};
        end

        case(g_state)
            2'd0: lcd_l2 = "     Start      ";
            2'd1: lcd_l2 = "     Ready      ";
            2'd2: lcd_l2 = " Wait for Green ";
            2'd3: begin
                if(result_ms == 16'hFFFF) 
                    lcd_l2 = "    Too Fast    ";
                else if(result_ms < 16'd200) 
                    lcd_l2 = "    Great       ";  // 0~199 ms
                else if(result_ms < 16'd300) 
                    lcd_l2 = "     Good       ";  // 200~299 ms
                else 
                    lcd_l2 = "     Slow       ";  // 300 ms 이상
            end
        endcase
    end
endmodule


module Piezo_Driver(
    input  clk,
    input  rst,
    input  en,
    output reg piezo_out
);

   
    localparam integer DIV_TONE   = 47800;
    localparam integer TICK_CNT   = 2_500_000;

    reg [31:0] tick_cnt;
    reg        tick;       

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            tick_cnt <= 0;
            tick     <= 0;
        end else if (!en) begin
            tick_cnt <= 0;
            tick     <= 0;
        end else begin
            if (tick_cnt >= TICK_CNT - 1) begin
                tick_cnt <= 0;
                tick     <= 1;
            end else begin
                tick_cnt <= tick_cnt + 1;
                tick     <= 0;
            end
        end
    end


    localparam integer NUM_STEPS = 6;

    reg [2:0] step_idx;        
    reg [3:0] step_len;       
    reg       step_sound_on;   
    reg [3:0] step_tick_cnt;   


    always @(*) begin
        case (step_idx)
            3'd0: begin step_sound_on = 1; step_len = 4'd2; end
            3'd1: begin step_sound_on = 0; step_len = 4'd1; end
            3'd2: begin step_sound_on = 1; step_len = 4'd2; end
            3'd3: begin step_sound_on = 0; step_len = 4'd1; end
            3'd4: begin step_sound_on = 1; step_len = 4'd6; end
            3'd5: begin step_sound_on = 0; step_len = 4'd6; end
            default: begin
                step_sound_on = 0;
                step_len      = 4'd2;
            end
        endcase
    end


    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            step_idx      <= 0;
            step_tick_cnt <= 0;
        end else if (!en) begin
            step_idx      <= 0;
            step_tick_cnt <= 0;
        end else begin
            if (tick) begin
                if (step_tick_cnt + 1 >= step_len) begin
                    step_tick_cnt <= 0;
                    if (step_idx == NUM_STEPS - 1)
                        step_idx <= 0;         
                    else
                        step_idx <= step_idx + 1;
                end else begin
                    step_tick_cnt <= step_tick_cnt + 1;
                end
            end
        end
    end


    reg [31:0] tone_cnt;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            tone_cnt  <= 0;
            piezo_out <= 0;
        end else if (!en || !step_sound_on) begin
            tone_cnt  <= 0;
            piezo_out <= 0;    
        end else begin
            if (tone_cnt >= DIV_TONE - 1) begin
                tone_cnt  <= 0;
                piezo_out <= ~piezo_out;   
            end else begin
                tone_cnt <= tone_cnt + 1;
            end
        end
    end

endmodule



module Seven_Seg_Driver(
    input clk,              
    input rst,              
    input [23:0] disp_data,                             
    input [5:0] dots,                            
    output reg [7:0] seg_data, 
    output reg [7:0] seg_com   
);

    reg [15:0] scan_cnt;
    wire tick_scan = (scan_cnt == 16'd49_999); 

    always @(posedge clk or negedge rst) begin
        if(!rst) 
            scan_cnt <= 0;
        else if(tick_scan) 
            scan_cnt <= 0;
        else 
            scan_cnt <= scan_cnt + 1;
    end


    reg [2:0] digit_sel; 
    always @(posedge clk or negedge rst) begin
        if(!rst) 
            digit_sel <= 0;
        else if(tick_scan) begin
            if(digit_sel >= 3'd5) digit_sel <= 0;
            else                   digit_sel <= digit_sel + 1;
        end
    end

   
    reg [3:0] hex_in;
    reg dot_in;

    always @(*) begin
        case(digit_sel)
            3'd0: begin seg_com = ~(8'b0000_0001); hex_in = disp_data[3:0];    dot_in = dots[0]; end // 우측 끝
            3'd1: begin seg_com = ~(8'b0000_0010); hex_in = disp_data[7:4];    dot_in = dots[1]; end
            3'd2: begin seg_com = ~(8'b0000_0100); hex_in = disp_data[11:8];   dot_in = dots[2]; end
            3'd3: begin seg_com = ~(8'b0000_1000); hex_in = disp_data[15:12];  dot_in = dots[3]; end
            3'd4: begin seg_com = ~(8'b0001_0000); hex_in = disp_data[19:16];  dot_in = dots[4]; end
            3'd5: begin seg_com = ~(8'b0010_0000); hex_in = disp_data[23:20];  dot_in = dots[5]; end
            default: begin seg_com = 8'hFF; hex_in = 4'h0; dot_in = 1'b0; end
        endcase
    end


    always @(*) begin
        case(hex_in)
            4'h0: seg_data[7:1] = 7'b1111110;
            4'h1: seg_data[7:1] = 7'b0110000;
            4'h2: seg_data[7:1] = 7'b1101101;
            4'h3: seg_data[7:1] = 7'b1111001;
            4'h4: seg_data[7:1] = 7'b0110011;
            4'h5: seg_data[7:1] = 7'b1011011;
            4'h6: seg_data[7:1] = 7'b1011111;
            4'h7: seg_data[7:1] = 7'b1110000;
            4'h8: seg_data[7:1] = 7'b1111111;
            4'h9: seg_data[7:1] = 7'b1111011;
            4'hA: seg_data[7:1] = 7'b1110111; // A
            4'hB: seg_data[7:1] = 7'b0011111; // b
            4'hC: seg_data[7:1] = 7'b1001110; // C
            4'hD: seg_data[7:1] = 7'b0111101; // d
            4'hE: seg_data[7:1] = 7'b1001111; // E
            4'hF: seg_data[7:1] = 7'b1000111; // F
            default: seg_data[7:1] = 7'b0000000;
        endcase
        seg_data[0] = dot_in; // DP
    end
endmodule


module Text_LCD_Driver(
    input clk, rst,
    input [127:0] line1_data, 
    input [127:0] line2_data, 
    output LCD_E,
    output reg LCD_RS, LCD_RW,
    output reg [7:0] LCD_DATA
);

    assign LCD_E = clk;

    reg [2:0] state;
    parameter DELAY       = 3'b000,
              FUNCTION_SET= 3'b001,
              ENTRY_MODE  = 3'b010,
              DISP_ONOFF  = 3'b011,
              LINE1       = 3'b100,
              LINE2       = 3'b101,
              DELAY_T     = 3'b110,
              CLEAR_DISP  = 3'b111;
              
    integer cnt;
    

    always @(posedge clk or negedge rst) begin
        if(!rst) 
            state <= DELAY;
        else begin
            case(state)
                DELAY:          if(cnt == 70) state <= FUNCTION_SET;
                FUNCTION_SET:   if(cnt == 30) state <= DISP_ONOFF;
                DISP_ONOFF:     if(cnt == 30) state <= ENTRY_MODE;
                ENTRY_MODE:     if(cnt == 30) state <= LINE1;
                LINE1:          if(cnt == 16) state <= LINE2;
                LINE2:          if(cnt == 16) state <= DELAY_T;
                DELAY_T:        if(cnt == 5) state <= LINE1;
                CLEAR_DISP:     if(cnt == 5) state <= LINE1;
                default:        state <= DELAY;
            endcase
        end
    end


    always @(posedge clk or negedge rst) begin
        if(!rst) 
            cnt <= 0;
        else begin
            case(state)
                DELAY:        if(cnt >= 70) cnt <= 0; else cnt <= cnt + 1;
                FUNCTION_SET: if(cnt >= 30) cnt <= 0; else cnt <= cnt + 1;
                DISP_ONOFF:   if(cnt >= 30) cnt <= 0; else cnt <= cnt + 1;
                ENTRY_MODE:   if(cnt >= 30) cnt <= 0; else cnt <= cnt + 1;
                LINE1, LINE2: if(cnt >= 16) cnt <= 0; else cnt <= cnt + 1;
                DELAY_T,
                CLEAR_DISP:   if(cnt >= 5)  cnt <= 0; else cnt <= cnt + 1;
                default:      cnt <= 0;
            endcase
        end
    end


    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            LCD_RS   <= 1'b1;
            LCD_RW   <= 1'b1;
            LCD_DATA <= 8'h00;
        end
        else begin
            case(state)
                FUNCTION_SET: begin
                    LCD_RS   <= 1'b0;
                    LCD_RW   <= 1'b0;
                    LCD_DATA <= 8'b0011_1000; 
                end
                DISP_ONOFF: begin
                    LCD_RS   <= 1'b0;
                    LCD_RW   <= 1'b0;
                    LCD_DATA <= 8'b0000_1100; 
                end
                ENTRY_MODE: begin
                    LCD_RS   <= 1'b0;
                    LCD_RW   <= 1'b0;
                    LCD_DATA <= 8'b0000_0110; 
                end

                LINE1: begin
                    if(cnt < 16) begin
                        LCD_RS   <= 1'b1;
                        LCD_RW   <= 1'b0;
                        LCD_DATA <= line1_data[(15-cnt)*8 +: 8];
                    end 
                    else begin
                        LCD_RS   <= 1'b0;
                        LCD_RW   <= 1'b0;
                        LCD_DATA <= 8'b1100_0000; 
                    end
                end

                LINE2: begin
                    if(cnt < 16) begin
                        LCD_RS   <= 1'b1;
                        LCD_RW   <= 1'b0;
                        LCD_DATA <= line2_data[(15-cnt)*8 +: 8];
                    end 
                    else begin
                        LCD_RS   <= 1'b0;
                        LCD_RW   <= 1'b0;
                        LCD_DATA <= 8'b1000_0000;
                    end
                end

                DELAY_T: begin
                    LCD_RS   <= 1'b0;
                    LCD_RW   <= 1'b0;
                    LCD_DATA <= 8'b0000_0010; 
                end
                CLEAR_DISP: begin
                    LCD_RS   <= 1'b0;
                    LCD_RW   <= 1'b0;
                    LCD_DATA <= 8'b0000_0001; 
                end
                default: begin
                    LCD_RS   <= 1'b1;
                    LCD_RW   <= 1'b1;
                    LCD_DATA <= 8'h00;
                end
            endcase
        end
    end

endmodule



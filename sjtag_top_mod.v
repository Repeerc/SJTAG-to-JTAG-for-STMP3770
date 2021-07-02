module sjtag_top_mod(
	input clk_50MHz,
	input rst_n,
	
	input nTRST,
	input TDI,
	input TCK,
	input TMS,
	output reg TDO,
	
	inout sjtag,
	inout sjtag_pull,
	
	output reg test_LED
);

parameter timeout1_192MHz_ticks	=  32'd64 ;
parameter timeout2_192MHz_ticks	=  32'd256 ;


wire clk_192MHz;

PLL pll0(
	.inclk0(clk_50MHz),
	.areset(~rst_n),
	.c0(clk_192MHz)
);



reg sjtag_oe;
reg sjtag_out;
reg sjtag_pull_oe;

assign sjtag = (sjtag_oe == 1) ? sjtag_out : 1'bz;
assign sjtag_pull = (sjtag_pull_oe == 1) ? 1'b1 : 1'bz;

reg[31:0] cnt;

reg TCK_r1,TCK_r2;	

reg sjtag_buf_r1, sjtag_buf_r2;

reg[7:0] stageA;
reg[31:0] cycle_192MHz;
reg[31:0] cycle_48MHz;
reg[7:0]send_cnt;

reg[31:0] timeout_cnt;

always @(negedge rst_n or posedge clk_192MHz )
begin
	if(rst_n == 0)
	begin
		stageA <= 0;
		sjtag_pull_oe <= 0;
		sjtag_out <= 0;
		sjtag_oe <= 0;
		cycle_192MHz <= 0;
		{TCK_r1, TCK_r2} <= 2'b11;
		{sjtag_buf_r1, sjtag_buf_r2} <= 2'b11;
		
		TDO <= 0;
		test_LED <= 0;
		timeout_cnt <= 0;
		cnt <= 0;
		
	end
	else
	begin

	cnt <= cnt + 1;
	if(cnt == 32'd192000000)
	begin
		cnt <= 0;
		test_LED <= !test_LED;
	end
	
	case(stageA)
		0: //Async Start Phase
			begin
				TCK_r1 <= TCK;
				TCK_r2 <= TCK_r1;	
				if((TCK_r2 == 0) && (TCK_r1 == 1))	//TCK上升沿
				begin
					
					stageA <= 1;
					cycle_192MHz <= 0;
					
					sjtag_out <= 1;
					sjtag_oe <= 1;
					sjtag_pull_oe <= 1;

				end
			end
		1: //Timing Mark Phase START
			begin
				cycle_192MHz <= cycle_192MHz + 1;
				if(cycle_192MHz == 3)
				begin
					sjtag_out <= 0;
					sjtag_oe <= 0;
					cycle_192MHz <= 0;
					timeout_cnt <= 0;
					stageA <= 2;
					{sjtag_buf_r1, sjtag_buf_r2} <= 2'b11;

				end
			end
		2: //Timing Mark Phase END
			begin
				sjtag_buf_r1 <= sjtag;
				sjtag_buf_r2 <= sjtag_buf_r1;
				if((sjtag_buf_r1 == 0) && (sjtag_buf_r2 == 1)) //SJTAG输入下降沿
					begin
					
							sjtag_pull_oe <= 0;
							stageA <= 3;
							cycle_192MHz <= 0;
							
					end
					
					
				timeout_cnt <= timeout_cnt + 1;
				if(timeout_cnt == timeout1_192MHz_ticks)
				begin
					stageA <= 8;		//超时，进入复位状态
					timeout_cnt <= 0;
				end
					
					
					
			end
		
		3:	//Wait for Sync
			begin
				cycle_192MHz <= cycle_192MHz + 1;
				if(cycle_192MHz == 3)
				begin
					stageA <= 4;
					
					send_cnt <= 0;
					cycle_48MHz <= 0;
					
					sjtag_out <= 0;
					sjtag_oe <= 1;
					
				end
			
			end
		4: //Debugger Send TDI, Mode Phase
			begin
				
				cycle_48MHz <= cycle_48MHz + 1;
				if(cycle_48MHz == 3)begin
				
					cycle_48MHz <= 0;
					send_cnt <= send_cnt + 1'd1;
					
					
					if(send_cnt == 7)
					begin
						timeout_cnt <= 0;
						sjtag_oe <= 0;
						stageA <= 5;
						{sjtag_buf_r1, sjtag_buf_r2} <= 2'b00;
					end
				end
				
				case(send_cnt)
					0:
						sjtag_out <= nTRST;
					2:
						sjtag_out <= TMS;
					4:
						sjtag_out <= TDI;
					6:
						sjtag_out <= 0;
				
				endcase
			end
		
		5: //STMP3770 Wait For Return Clock Phase
			begin
				
				sjtag_buf_r1 <= sjtag;
				sjtag_buf_r2 <= sjtag_buf_r1;
				if((sjtag_buf_r1 == 1) && (sjtag_buf_r2 == 0)) //SJTAG输入上升沿
				begin
					stageA <= 6;
					cycle_192MHz <= 0;
				end
				
				
				timeout_cnt <= timeout_cnt + 1;
				if(timeout_cnt == timeout2_192MHz_ticks)
					begin
						stageA <= 8;		//超时，进入复位状态
						timeout_cnt <= 0;
					end
				
				
			end
		6: //STMP3770 Sends TDO and Return Clock Timing Phase
			begin
				cycle_192MHz <= cycle_192MHz + 1;
				if(cycle_192MHz == 8)begin
					TDO <= sjtag;
					stageA <= 7;
					cycle_192MHz <= 0;
				end
			end
		7:	//STMP3770 Terminate Phase
			begin
				cycle_192MHz <= cycle_192MHz + 1;
				if(cycle_192MHz == 3)
				begin
					stageA <= 8;
					sjtag_out <= 0;
					sjtag_oe <= 1;
					cycle_192MHz <= 0;
				end
			end
		8:	//Reset State Machine
			begin
				cycle_192MHz <= cycle_192MHz + 1;
				if(cycle_192MHz == 3)
				begin
					sjtag_oe <= 0;
				end
			
			
				if(cycle_192MHz == 6)
				begin
					stageA <= 0;
					sjtag_pull_oe <= 0;
					sjtag_out <= 0;
					sjtag_oe <= 0;
					cycle_192MHz <= 0;
					{TCK_r1, TCK_r2} <= 2'b11;
					{sjtag_buf_r1, sjtag_buf_r2} <= 2'b11;
				end
			end
		
	endcase
	
	end
end

endmodule


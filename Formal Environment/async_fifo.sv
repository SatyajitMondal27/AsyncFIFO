/* This is an asynchronous FIFO, data is written in the wclk domai and read in the rclk domain.
The design uses gray coded read and write pointers and two stage synchronizers to communicate the FIFO state across the clock-domain boundary
The FIFO has 16 entries(depth)
Each entry is 64 bits wide
The pointer is 5 bits even though it need 4 bits. 
Extra bit is used to distinguish full from empty when address wraps around

*/


module async_fifo 
#(
	parameter DSIZE = 64, // width of each FIFO entry
	parameter ASIZE = 5, // Width of the read and write points, 4 bits for 16 values and 1 extra bit to distinguish full and empty
	parameter MEMSIZE = 16 // should be 2 ^ (ASIZE-1)
)
(
	rdata, 
	rempty,
	rclk,
	ren,
	wdata,
	wfull,
	wclk,
	wval,
	wreset,
	rreset
	);

//Inputs and Outputs
output  [DSIZE-1:0] 	rdata; // data being read
output			rempty; // indicates that FIFO is empty, read not possible
output 			wfull; // indicates that FIFO is full, write is not possible
`ifdef FORMAL
(* anyseq *) input logic 	[DSIZE-1:0]	wdata; // data being written to FIFO
(* anyseq *) input logic 			wval; //write valid signal*
(* anyseq *) input logic 			ren; // read enable signal*
`else 
input	[DSIZE-1:0]	wdata; // data being written to FIFO
input			wval; //write valid signal*
input			ren; // read enable signal*
`endif


input			rclk;// clock in reading domain
input			wclk;// clock in writing domain
input 			wreset;// write domain reset
input			rreset;// read domain reset

//Internal Registers
reg	[ASIZE-1:0]	g_wptr; //gray coded write pointer
reg	[ASIZE-1:0]	g_rptr; //gray coded read pointer

reg	[ASIZE-1:0]	g_rsync1, g_rsync2; // 2 flip flop synchronizer outputs for read domain pointer
// g_rptr -FF-> g_rsync1 -FF-> g_rsync2
reg	[ASIZE-1:0]	b_rsync1, b_rsync2;

reg	[ASIZE-1:0]	g_wsync1, g_wsync2;// 2 flip flop synchronizer outputs for write domain pointer
// g_wptr -FF-> g_wsync1 -FF-> g_wsync2
//Memory
reg	[DSIZE-1:0] 	fifo[MEMSIZE-1:0]; //FIFO memory, 16 64-bit entries can be stored

wire [ASIZE-1:0] b_wptr; //current binary write pointer
wire [ASIZE-1:0] b_wptr_next;//next binary write pointer
wire [ASIZE-1:0] g_wptr_next;//next gray code write pointer
wire [ASIZE-1:0] b_rptr;// current binary read pointer
wire [ASIZE-1:0] b_rptr_next;//next binary read pointer
wire [ASIZE-1:0] g_rptr_next;//next gray code read pointer

/********************************************************************
COMBINATIONAL LOGIC
********************************************************************/

//convert gray to binary
assign b_wptr[ASIZE-1:0] = ({1'b0, b_wptr[ASIZE-1:1]} ^ g_wptr[ASIZE-1:0]);
assign b_rptr[ASIZE-1:0] = ({1'b0, b_rptr[ASIZE-1:1]} ^ g_rptr[ASIZE-1:0]);
/* gray code to binary conversion is performed
GRAY -----> BINARY keep MSB and XOR newest MSB to binary with current gray bit
b[4] = g[4]
b[3] = b[4] XOR g[3]
b[2] = b[3] XOR g[2]
b[1] = b[2] XOR g[1]
b[0] = b[1] XOR g[0]
*/
//increment
assign b_wptr_next = b_wptr + 1;
assign b_rptr_next = b_rptr + 1;
// next binary pointer = current pointer value plus 1

//convert binary to gray
assign g_wptr_next[ASIZE-1:0] = {1'b0, b_wptr_next[ASIZE-1:1]} ^ b_wptr_next[ASIZE-1:0];
assign g_rptr_next[ASIZE-1:0] = {1'b0, b_rptr_next[ASIZE-1:1]} ^ b_rptr_next[ASIZE-1:0];
// same logic as gray to binary but using next value to binary write and read pointers

//full and empty signals
assign wfull =  (g_wptr[ASIZE-1]   != g_rsync2[ASIZE-1]  ) && 
		(g_wptr[ASIZE-2]   != g_rsync2[ASIZE-2]  ) &&
		(g_wptr[ASIZE-3:0] == g_rsync2[ASIZE-3:0]) ||
		(wreset || rreset);
/*
The wfull signal indicates that the FIFO is full and cannot accept new values
The condition defined here is the gray code condition that,
 write pointer is one full FIFO depth ahead of read pointer.
 Signal is also high when wreset or rreset is on
*/

assign rempty =  (g_wsync2[ASIZE-1:0] == g_rptr[ASIZE-1:0]) ||
	         (wreset || rreset);
			 
/*
The rempty signal indicates that the FIFO is empty and cannot output any values
The condition defined here says the FIFO is empty when read pointer is equal to the synchronized write pointer
*/

//output values
assign rdata = fifo[b_rptr[ASIZE-2:0]];//output of the FIFO
/********************************************************************
SEQUENTIAL LOGIC
********************************************************************/

//transfer register values
always @(posedge rclk) begin
	if (rreset) begin
		g_rptr <= 0;	//at reset read pointer reset to zero
	end
	else if (ren && !rempty) begin 
		g_rptr <= g_rptr_next; // if read enable is high and FIFO is not empty read pointer incremented
	end

	g_wsync1 <= g_wptr; 
	g_wsync2 <= g_wsync1;//2 flip flip synchronizer for write pointer operating in read clock frequency
end

always @(posedge wclk) begin
	if (wreset) begin
		g_wptr <= 0;// at reset write pointer reset to 0
	end
	else if (wval && !wfull) begin //if write valid is high and and FIFO is not full
		fifo[b_wptr[ASIZE-2:0]] <= wdata;// wdata is stored in the FIFO
		g_wptr <= g_wptr_next;// write pointer incremented to next value
	end

	g_rsync1 <= g_rptr;
	g_rsync2 <= g_rsync1;// two flip flop synchronizer of read pointer operating in write clock frequency

	
end
`ifdef FORMAL
	// Formal verification of the module

	//Testing reset
	(* gclk *) reg formal_timestep;

	always @(posedge formal_timestep)
		assume(wclk == !$past(wclk));

	initial derived_counter = 1;

	always @(posedge formal_timestep)
	    derived_counter <= derived_counter + 1'b1;

	always @(posedge formal_timestep) begin
    	assume(rclk == derived_counter[1]);
	end

initial assume 	(ren==0 && wdata==0 && wval==0 && rreset==1 && wreset==1 && b_rptr==0 && b_wptr==0);

integer i;
logic [1:0]derived_counter;
initial begin
    for (i = 0; i < MEMSIZE; i = i + 1)
        fifo[i] = {DSIZE{1'b0}};
end

logic [ASIZE-1:0] b_rsync2;
logic f_past_valid_r;
logic f_past_valid_w;

initial f_past_valid_r=0;
initial f_past_valid_w=0;

always_ff@(posedge rclk)
	f_past_valid_r<=1'b1;

always_ff@(posedge wclk)
	f_past_valid_w<=1'b1;


assign b_rsync2 = g_rsync2 ^ (g_rsync2 >> 1);//synchronized binary write pointer

	// test to check if write reset is working

	always_ff @(posedge wclk) begin
		if(f_past_valid_w && $past(wreset))
			assert(g_wptr==0);
	end

	always_ff @(posedge rclk) begin
		if(f_past_valid_r && $past(rreset))
			assert(g_rptr==0);
	end


	//assertions about read pointer and write pointer next
	always@(*) begin
			assert(b_rptr_next-b_rptr==1'b1);
	end

	//assertions about write pointer and read pointer next
	always@(*) begin
			assert(b_wptr_next-b_wptr==1'b1);
	end

	//assertion to check if full signal is working
	always@(*)begin
		if(wreset||rreset)
			assert(wfull==1);	// on either reset wfull is high
		else if(b_rsync2[ASIZE-2:0]-b_wptr[ASIZE-2:0]==16)
			assert(wfull==1);	// FIFO is full if synchronized write pointer is 16 steps ahead of read pointer

	end

	//assertion to check if empty signal is working
	always@(*)begin
		if(wreset||rreset)
			assert(rempty==1);		// on either reset rempty is high
		else if(g_rptr==g_wsync2)
			assert(rempty==1);		// FIFO is empty if synchronized write pointer is equal to read pointer 
	end

	// assertions to verify read operations
	always_ff @(posedge rclk)begin
		if(f_past_valid_r && !$past(rreset))begin
			 if (!$past(ren) || $past(rempty))
				assert(rdata==0); // if read enable is low or if fifo is empty read is zero
			else if($past(ren) && !$past(rempty) && $stable(fifo[$past(b_rptr[ASIZE-2:0])]))begin// valid read request where value stored in fifo is not changing in the write domain clock speed
				assert(rdata==fifo[$past(b_rptr[ASIZE-2:0])]);
			end
		end
	end
	
	// assertions to verify write operations
	always_ff @(posedge wclk)begin
		if(f_past_valid_w && !$past(wreset))begin
			if($past(wval) && !$past(wfull))begin
				assert(g_wptr==$past(g_wptr_next)); // on a valid write in the next clock cycle, write pointer incremented by 1
				assert(fifo[$past(b_wptr[ASIZE-2:0])]== $past(wdata)); // on a valid write in the next clock cycle fifo value at previous write pointer location == wdata in previous cycle		
			end
			// if fifo is full or wval is low writes should not take place
			else if($past(wval) || !$past(wfull))begin
				assert(g_wptr!=$past(g_wptr_next));// write pointer should not be incremented
			//value stored in fifo and value on wdata can be same. write operation should not occur
			end

		end
	end	

`endif
endmodule
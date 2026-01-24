TYPE DUT_OUTPUTS :
STRUCT
TWB1_cmd_fwd : BIT; //Run conveyor forward (Length: 2000mm)
TWB2_cmd_fwd : BIT; //Run conveyor forward (Length: 4000mm)
TWB3_cmd_fwd : BIT; //Run conveyor forward (Length: 8000mm)
TWB4_cmd_fwd : BIT; //Run conveyor forward (Length: 2000mm)
TWB1_cmd_bwd : BIT; //Run conveyor backward (Length: 2000mm)
TWB2_cmd_bwd : BIT; //Run conveyor backward (Length: 4000mm)
TWB3_cmd_bwd : BIT; //Run conveyor backward (Length: 8000mm)
TWB4_cmd_bwd : BIT; //Run conveyor backward (Length: 2000mm)
em1_cmd_emit : BIT; //Trigger item spawn
em2_cmd_emit : BIT; //Trigger item spawn
destroyer_cmd_on : BIT; //Enable destroyer
destroyer2_cmd_on : BIT; //Enable destroyer
SPARE_OUTPUT_01 : BIT; //Spare bit
SPARE_OUTPUT_02 : BIT; //Spare bit
SPARE_OUTPUT_03 : BIT; //Spare bit
SPARE_OUTPUT_04 : BIT; //Spare bit
Rise1_cmd_left : BIT; //Command divert left (belt forward)
Rise1_cmd_right : BIT; //Command divert right (belt backward)
SPARE_OUTPUT_05 : BIT; //Spare bit
SPARE_OUTPUT_06 : BIT; //Spare bit
SPARE_OUTPUT_07 : BIT; //Spare bit
SPARE_OUTPUT_08 : BIT; //Spare bit
SPARE_OUTPUT_09 : BIT; //Spare bit
SPARE_OUTPUT_10 : BIT; //Spare bit
SPARE_OUTPUT_11 : BIT; //Spare bit
SPARE_OUTPUT_12 : BIT; //Spare bit
SPARE_OUTPUT_13 : BIT; //Spare bit
SPARE_OUTPUT_14 : BIT; //Spare bit









END_STRUCT
END_TYPE
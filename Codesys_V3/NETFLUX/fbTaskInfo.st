(*
Function Block: fbTaskInfo
Purpose: Retrieves and processes current task timing information. Works only with TaskCyclic.
Outputs:
  - lrTaskCycle: Task cycle time in milliseconds (LREAL)
  - rTaskCycle: Task cycle time in milliseconds (REAL)
  - xTaskCycle: Task cycle time as TIME value. works only with task >= 1ms
*)
FUNCTION_BLOCK fbTaskInfo
VAR
    _stTaskInfo : POINTER TO Task_Info2;              // Pointer to task information structure
    _IecTaskGetCurrent : UDINT;                      // Result of IecTaskGetCurrent call
    _IecTaskGetInfo3 : UDINT;                        // Result of IecTaskGetInfo3 call
    _ptrIecTaskGetCurrent : POINTER TO UDINT := ADR(_IecTaskGetCurrent);    // Pointer for current task result
    _ptrIecTaskGetInfo3 : POINTER TO UDINT := ADR(_IecTaskGetInfo3);        // Pointer for task info result
END_VAR
VAR_OUTPUT
    lrTaskCycle : LREAL;       // High precision cycle time in ms
    rTaskCycle : REAL;         // Standard precision cycle time in ms
    tTaskCycle : TIME;         // Cycle time as TIME data type
END_VAR

// === IMPLEMENTATION ===
// Retrieve current task handle and task information
_stTaskInfo := IecTaskGetInfo3(
    hIecTask := IecTaskGetCurrent(pResult:= _ptrIecTaskGetCurrent),
    pResult:= _ptrIecTaskGetInfo3
);

// Process timing information based on task type
IF _stTaskInfo^.KindOfTask = 16#0 THEN        // Fixed interval execution, works only with TaskCyclic - KindOfTask
	 // Calculate cycle time including jitter for cyclic tasks
        lrTaskCycle := (DWORD_TO_LREAL(_stTaskInfo^.dwInterval) + DINT_TO_LREAL(_stTaskInfo^.iJitter)) / 1000.0;
        rTaskCycle := LREAL_TO_REAL(lrTaskCycle);
        tTaskCycle := REAL_TO_TIME(rTaskCycle);
END_IF
unit water;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin,
  ExtCtrls;

type


  { TForm1 }

  TForm1 = class(TForm)
    BSolve: TButton;
    BUndo: TButton;
    CBSingle: TCheckBox;
    Panel1: TPanel;
    TBRandom: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Memo1: TMemo;
    NColorsSpin: TSpinEdit;
    NFreeVialSpin: TSpinEdit;
    NVolumeSpin: TSpinEdit;
    procedure BSolveClick(Sender: TObject);
    procedure BUndoClick(Sender: TObject);
    procedure CBSingleChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure NColorsSpinChange(Sender: TObject);
    procedure NFreeVialSpinChange(Sender: TObject);
    procedure NVolumeSpinChange(Sender: TObject);
    procedure Panel1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure Panel1Paint(Sender: TObject);
    procedure TBRandomClick(Sender: TObject);
  private

  public

  end;

  {$minEnumSize 1}
  TCls = (EMPTY, BLUE, RED, LIME, YELLOW, FUCHSIA, AQUA, GRAY, ROSE, OLIVE,
    BROWN, LBROWN, GREEN, LBLUE, BLACK);
  {$minEnumSize normal}
  TState = array of array of TList;
  THash = array of array of array of UInt32;
  TVialsDef = array of array of TCls;
  TColDef = array of TColor;

  TVialTopInfo = record
    empty: integer; //empty volume of vial
    topcol: integer;//surface color, 0 for empty vial
    topvol: integer;//volume of surface color, NVOLUME for empty vial
  end;

  TMoveInfo = record
    srcVial: UInt8; //source and destination of a move
    dstVial: UInt8;
    merged: boolean;//move reduced number of blocks or keeps number
  end;

  { TVial }

  TVial = class
  public
    color: array of TCls;//colors starting from top of vial
    pos: UInt8; //Index of vial
    constructor Create(var c: array of TCls; p: UInt8);
    destructor Destroy; override;
    function getTopInfo: TVialTopInfo;
    function vialBlocks: integer;
  end;

  { TNode }

  TNode = class
  public
    vial: array of TVial;
    hash: UInt32;
    mvInfo: TMoveInfo;
    constructor Create(t: TVialsDef);
    constructor Create(node: TNode);
    destructor Destroy; override;
    procedure printRaw(w: TMemo);
    procedure print(w: TMemo);
    function getHash: UInt32;
    procedure writeHashbit;
    function isHashedQ: boolean;
    function nodeBlocks: integer;
    function equalQ(node: TNode): boolean;
    function lastmoves: string;
    function Nlastmoves: integer;
    function emptyVials: integer;
  end;

{
  0077FF ORANGE
  000066 DKRED
  E16941 ROYAL
  51B5F8 SANDY
  56719C LTBROWN
  690D9F MYMAROON
  6C37E5 PNKRED
  5252D9 LTRED 
  33FF99 LIME 
  80FF00 BGREEN 
}
{
    TColor($5252D9)      LTRED
    clBlue               BLUE
    TColor($000066)      DKRED
    clGreen              DKGREEN
    clOlive              OLIVE
    TColor($33FF99)      LIME
    TColor($E16941)      ROYAL
    TColor($0077FF)      ORANGE
    clYellow             YELLOW
    clPurple             PURPLE
    TColor($690D9F)      MAROON
    clFuchsia            MAGENTA
    TColor($51B5F8)      SANDY
    clRed                RED
    clAqua               CYAN
    clGray               GREY
    TColor($56719C)      BROWN
    TColor($80FF00)      BGREEN?
}


const
  cols: array of TColor = (
    clWhite,
    TColor($5252D9),  clBlue,           TColor($000066),  clGreen,  clOlive,          TColor($33FF99),
    TColor($E16941),  TColor($0077FF),  clYellow,         clPurple, TColor($690D9F),  clFuchsia,
    TColor($51B5F8),  clRed,            clAqua,           clGray,   TColor($56719C),  TColor($80FF00),
    clBlack);
  XOFF = 10;
  YOFF = 20;
  APPNAME = 'ColorSortOptimalSolver';
  N_NOTDECREASE = 1000;
  N_HISTORY = 1000;
  N_MAXNODES = 2000000;//abort if reached to avoid heap getting to big

var
  Form1: TForm1;
  NCOLORS, NVIALS, NEMPTYVIALS, NVOLUME, NEXTRA: integer;
  hashbits: array of UInt64;
  vialsDefHist: array [0..N_HISTORY] of TVialsDef;
  undoHist: integer;
  stop: boolean;// abort optimal solving
  shifted: boolean;// shift state
  singleMode: boolean;//Single Block Mode  or Multi Block Mode

implementation

uses Math;

{$R *.lfm}

var
  state: TState;
  hsh: THash;
  globVialdef: TVialsDef;
  srcVial, dstVial, srcblock, dstblock: integer;

function compare(v1, v2: TVial): integer;
var
  i: integer;
begin
  for i := 0 to NVOLUME - 1 do
  begin
    if v1.color[i] < v2.color[i] then
      exit(1);
    if v1.color[i] > v2.color[i] then
      exit(-1);
  end;
  Result := 0;
end;

procedure sortNode(var node: TNode; iLo, iHi: integer);
var
  Lo, Hi: integer;
  Pivot, T: TVial;
begin
  Lo := iLo;
  Hi := iHi;
  Pivot := node.vial[(Lo + Hi) div 2];
  repeat
    while compare(node.vial[Lo], Pivot) = 1 do
      Inc(Lo);
    while compare(node.vial[Hi], Pivot) = -1 do
      Dec(Hi);
    if Lo <= Hi then
    begin
      T := node.vial[Lo];
      node.vial[Lo] := node.vial[Hi];
      node.vial[Hi] := T;
      Inc(Lo);
      Dec(Hi);
    end;
  until Lo > Hi;
  if Hi > iLo then
    sortNode(node, iLo, Hi);
  if Lo < iHi then
    sortNode(node, Lo, iHi);
end;


procedure init(global: boolean = True);
var
  i, j, k: integer;
begin

  NCOLORS := Form1.NColorsSpin.Value;
  NEMPTYVIALS := Form1.NFreeVialSpin.Value;
  NVOLUME := Form1.NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;
  singlemode := Form1.CBSingle.Checked;

  Randomize;
  SetLength(state, 0, 0);
  //We allow N_NOTDECREASE moves which do not decrease total block number
  SetLength(state, NCOLORS * (NVOLUME - 1) + 1, N_NOTDECREASE + 1);
  SetLength(hsh, 0, 0, 0);
  SetLength(hsh, NCOLORS + 1, NVOLUME, NVIALS);
  for i := 0 to NCOLORS do
    for j := 0 to NVOLUME - 1 do
      for k := 0 to NVIALS - 1 do
        hsh[i, j, k] := Random(4294967295); //color, position, vial
  SetLength(hashbits, 67108864);
  for i := 0 to 67108864 - 1 do
    hashbits[i] := 0;

  if global then //Reset all vials
  begin
    SetLength(globVialdef, NVIALS, NVOLUME);
    for i := 0 to NCOLORS - 1 do
      for j := 0 to NVOLUME - 1 do
        globVialdef[i, j] := TCls(i + 1);
    for i := NCOLORS to NVIALS - 1 do
      for j := 0 to NVOLUME - 1 do
        globVialdef[i, j] := EMPTY;
    undoHist := -1;
    Form1.Caption := APPNAME;
    Form1.Panel1.Invalidate;
  end;

  srcVial := -1;
  dstVial := -1;
  srcblock := -1;
  dstblock := -1;
  //shifted:=false;
end;



function nearoptimalSolution_single(nblock, y0: integer): string;
var
  i, j, k, x, y, src, dst, ks, kd, vmin, solLength, addmove: integer;
  nd, ndcand: TNode;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  resback, ft, mv2: string;
  A: TStringArray;
label
  freemem;
begin
  if stop then
  begin
    Result := 'Computation aborted!';
    goto freemem;
  end;
  if state[nblock - NCOLORS, y0].Count = 0 then
  begin
    Result := 'No solution. Undo moves or create new puzzle.';
    goto freemem;
  end;
  if nblock = NCOLORS then  //puzzle is almost solved
  begin
    Result := TNode(state[0, 0][0]).lastmoves;
    goto freemem;
  end;

  Result := '';
  if NVIALS > 9 then
    ft := '%2d->%2d,'
  else
    ft := '%d->%d,';

  x := nblock - NCOLORS;
  y := y0;
  nd := TNode(state[x, y][0]);
  addMove := nd.Nlastmoves; //add last moves seperate
  mv2 := nd.lastmoves;

  src := nd.mvInfo.srcVial;
  dst := nd.mvInfo.dstVial;
  Result := Result + Format(ft, [src + 1, dst + 1]);
  if nd.mvInfo.merged then
  begin
    Dec(x);
  end
  else
  begin
    Dec(y);
  end;

  solLength := 1;
  while (x <> 0) or (y <> 0) do
  begin
    ndlist := state[x, y];
    for i := 0 to ndlist.Count - 1 do
    begin
      ndcand := TNode.Create(TNode(ndlist.Items[i]));

      ks := 0;
      while ndcand.vial[ks].pos <> src do
        Inc(ks);
      kd := 0;
      while ndcand.vial[kd].pos <> dst do
        Inc(kd);

      viS := ndcand.vial[ks].getTopInfo;
      viD := ndcand.vial[kd].getTopInfo;
      if viS.empty = NVOLUME then
      begin
        ndcand.Free;
        continue;//source is empty vial
      end;

      if (viD.empty = 0)(*destination vial full*) or
        ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
        (*destination not empty and top colors different*) or
        ((viD.empty = NVOLUME) and (viS.empty = NVOLUME - 1))
      (*destination empty and only one ball in source*) then
      begin
        ndcand.Free;
        continue;
      end;
      ndcand.vial[kd].color[viD.empty - 1] := TCls(viS.topcol);
      ndcand.vial[ks].color[viS.empty] := EMPTY;

      sortNode(ndcand, 0, NVIALS - 1);
      if nd.equalQ(ndcand) then
      begin
        ndcand.Free;
        nd := TNode(ndlist.Items[i]);
        src := nd.mvInfo.srcVial;
        dst := nd.mvInfo.dstVial;
        Result := Result + Format(ft, [src + 1, dst + 1]);
        Inc(solLength);
        if nd.mvInfo.merged then
          Dec(x)
        else
          Dec(y);
        break;
      end;
      ndcand.Free;
    end;//i;
  end;

  Form1.Memo1.Lines.Add(Format('Near-optimal solution in %d moves',
    [solLength + addMove]));

  A := Result.Split(','); //Reverse move string
  k := Length(A);
  resback := '';
  for i := k - 1 downto 0 do
  begin
    resback := resback + A[i] + '  ';
    if (k - i - 1) mod 10 = 0 then
      resback := resback + sLineBreak;
  end;
  Result := resback + mv2;
  freemem:
    for i := 0 to nblock - NCOLORS do
      for j := 0 to y0 + 1 do
      begin
        for k := 0 to state[i, j].Count - 1 do
          TNode(state[i, j][k]).Free;
        state[i, j].Free;
      end;
end;

procedure solve_single(def: TVialsDef);
var
  nd, ndnew: TNode;
  nblockV, i, j, k, lmin, kmin, x, y, ks, kd, newnodes, total: integer;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  blockdecreaseQ, solutionFound: boolean;
  tmp: Pointer;
label
  abort;
begin
  init(False); //false: do not reset color definitions in display
  nd := TNode.Create(def);
  sortNode(nd, 0, NVIALS - 1);

  y := 0;
  nblockV := nd.nodeBlocks + nd.emptyVials - NEMPTYVIALS;//total number of blocks
  for i := 0 to nblockV - NCOLORS do
    state[i, y] := TList.Create;
  state[0, 0].Add(nd);
  nd.writeHashbit;
  total := 1;

  solutionFound := False;
  repeat
    newnodes := 0;
    for i := 0 to nblockV - NCOLORS do
      state[i, y + 1] := TList.Create;  //prepare next column
    for x := 0 to nblockV - NCOLORS - 1 do
    begin
      if stop then
        goto abort;
      Application.ProcessMessages;

      ndlist := state[x, y];
      for i := 0 to ndlist.Count - 1 do
      begin
        nd := TNode(ndlist.Items[i]);
        for ks := 0 to NVIALS - 1 do
        begin
          viS := nd.vial[ks].getTopInfo;
          if viS.empty = NVOLUME then
            continue;//source is empty vial
          for kd := 0 to NVIALS - 1 do
          begin
            if kd = ks then
              continue;//source vial= destination vial
            viD := nd.vial[kd].getTopInfo;

            if (viD.empty = 0)(*destination vial full*) or
              ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
              (*destination not empty and top colors different*) or
              ((viD.empty = NVOLUME) and (viS.empty = NVOLUME - 1))
            (*destination empty and only one ball in source*) then
              continue;

            if (viS.topvol = 1) and (viS.empty <> NVOLUME - 1) then
              blockdecreaseQ := True //exactly one block on different blocks
            else
              blockdecreaseQ := False;
            ndnew := TNode.Create(nd);
            ndnew.vial[kd].color[viD.empty - 1] := TCls(viS.topcol);
            ndnew.vial[ks].color[viS.empty] := EMPTY;
            sortNode(ndnew, 0, NVIALS - 1);
            ndnew.hash := ndnew.getHash;
            if ndnew.isHashedQ then
            begin
              ndnew.Free;
              continue; //node presumely already exists, no hash collision detection
            end;
            ndnew.writeHashbit;
            Inc(total);
            if total > N_MAXNODES then
            begin
              Form1.Memo1.Lines.Add('');
              Form1.Memo1.Lines.Add(Format('Node limit %d exceeded!', [N_MAXNODES]));
              stop := True;
              goto abort;
            end;
            ndnew.mvInfo.srcVial := nd.vial[ks].pos;
            ndnew.mvInfo.dstVial := nd.vial[kd].pos;

            if blockdecreaseQ then
            begin
              ndnew.mvInfo.merged := True;
              state[x + 1, y].Add(ndnew);
            end
            else
            begin
              ndnew.mvInfo.merged := False;
              state[x, y + 1].Add(ndnew);
              Inc(newnodes);//new node in next column
            end;
          end;//destination vial;
        end;//source vial
      end;//list interation
    end; //column interation
    if state[nblockV - NCOLORS, y].Count > 0 then
      solutionFound := True;
    Inc(y); //next column
    // Form1.Memo1.Lines.Add(Format('%d',[GetHeapStatus.TotalAllocated]));
  until solutionFound or (newnodes = 0);

  if solutionfound then
  begin
    //Form1.Memo1.Lines.Add(IntToStr(nblockV) + ' ' + IntToStr(NCOLORS));
    //for i := 0 to nblockV - NCOLORS do
    //  for j := 0 to y - 1 do
    //    Form1.Memo1.Lines.Add(IntToStr(i) + ' ' + IntToStr(j) + ' ' +
    //      IntToStr(state[i, j].Count));

    lmin := 99999; //select solution with the fewest correction moves
    for k := 0 to state[nblockV - NCOLORS, y - 1].Count - 1 do
    begin
      //TNode(state[nblockV - NCOLORS, y - 1][k]).printRaw(Form1.Memo1);
      j := TNode(state[nblockV - NCOLORS, y - 1][k]).Nlastmoves;
      if j < lmin then
      begin
        kmin := k;
        lmin := j;
      end;
    end;
    tmp := state[nblockV - NCOLORS, y - 1][0];
    state[nblockV - NCOLORS, y - 1][0] := state[nblockV - NCOLORS, y - 1][kmin];
    state[nblockV - NCOLORS, y - 1][kmin] := tmp;
  end;
  Form1.Memo1.Lines.Add('');
  Form1.Memo1.Lines.Add(Format('%d nodes generated', [total]));
  Form1.Memo1.Lines.Add(nearoptimalSolution_single(nblockV, y - 1));
  Exit;
  abort:
    Form1.Memo1.Lines.Add(nearoptimalSolution_single(nblockV, y));
end;

function optimalSolution_multi(nblock, y0: integer): string;
var
  i, j, k, x, y, src, dst, ks, kd, vmin, solLength: integer;
  nd, ndcand: TNode;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  resback, ft: string;
  A: TStringArray;
label
  freemem;
begin
  if stop then
  begin
    Result := 'Computation aborted!';
    goto freemem;
  end;
  if state[nblock - NCOLORS, y0].Count = 0 then
  begin
    Result := 'No solution. Undo moves or create new puzzle.';
    goto freemem;
  end;
  if nblock = NCOLORS then
  begin
    Result := 'Puzzle already solved!';
    goto freemem;
  end;

  Result := '';
  if NVIALS > 9 then
    ft := '%2d->%2d,'
  else
    ft := '%d->%d,';

  x := nblock - NCOLORS;
  y := y0;
  nd := TNode(state[x, y][0]);

  src := nd.mvInfo.srcVial;
  dst := nd.mvInfo.dstVial;
  Result := Result + Format(ft, [src + 1, dst + 1]);
  if nd.mvInfo.merged then
  begin
    Dec(x);
  end
  else
  begin
    Dec(y);
  end;

  solLength := 1;
  while (x <> 0) or (y <> 0) do
  begin
    ndlist := state[x, y];
    for i := 0 to ndlist.Count - 1 do
    begin
      ndcand := TNode.Create(TNode(ndlist.Items[i]));

      ks := 0;
      while ndcand.vial[ks].pos <> src do
        Inc(ks);
      kd := 0;
      while ndcand.vial[kd].pos <> dst do
        Inc(kd);

      viS := ndcand.vial[ks].getTopInfo;
      viD := ndcand.vial[kd].getTopInfo;
      if viS.empty = NVOLUME then
      begin
        ndcand.Free;
        continue;//source is empty vial
      end;

      if (viD.empty = 0)(*destination vial full*) or
        ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
        (*destination not empty and top colors different*) or
        ((viD.empty = NVOLUME) and (viS.topvol + viS.empty = NVOLUME))
      (*destination empty and only one color in source*) then
      begin
        ndcand.Free;
        continue;
      end;
      vmin := Min(viD.empty, viS.topvol);
      for j := 1 to vmin do
      begin
        ndcand.vial[kd].color[viD.empty - j] := TCls(viS.topcol);
        ndcand.vial[ks].color[vis.empty - 1 + j] := EMPTY;
      end;

      sortNode(ndcand, 0, NVIALS - 1);
      if nd.equalQ(ndcand) then
      begin
        ndcand.Free;
        nd := TNode(ndlist.Items[i]);
        src := nd.mvInfo.srcVial;
        dst := nd.mvInfo.dstVial;
        Result := Result + Format(ft, [src + 1, dst + 1]);
        Inc(solLength);
        if nd.mvInfo.merged then
          Dec(x)
        else
          Dec(y);
        break;
      end;
      ndcand.Free;
    end;//i;
  end;


  Form1.Memo1.Lines.Add(Format('Optimal solution in %d moves', [solLength]));


  A := Result.Split(','); //Reverse move string
  k := Length(A);
  resback := '';
  for i := k - 1 downto 0 do
  begin
    resback := resback + A[i] + '  ';
    if (k - i - 1) mod 10 = 0 then
      resback := resback + sLineBreak;
  end;
  // Form1.Memo1.Lines.Add(resback);
  Result := resback;
  freemem:
    for i := 0 to nblock - NCOLORS do
      for j := 0 to y0 + 1 do

      begin
        for k := 0 to state[i, j].Count - 1 do
          TNode(state[i, j].Items[k]).Free;
        state[i, j].Free;
      end;
end;

procedure solve_multi(def: TVialsDef);
var
  nd, ndnew: TNode;
  nblockV, i, j, newnodes, x, y, ks, kd, vmin, total: integer;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  blockdecreaseQ, solutionFound: boolean;
label
  abort;
begin
  init(False); //false: do not reset color definitions in display
  nd := TNode.Create(def);
  sortNode(nd, 0, NVIALS - 1);

  y := 0;
  nblockV := nd.nodeBlocks;//total number of blocks in start configuration
  for i := 0 to nblockV - NCOLORS do
    state[i, y] := TList.Create;
  state[0, 0].Add(nd);
  nd.writeHashbit;
  total := 1;


  solutionFound := False;
  repeat
    newnodes := 0;
    for i := 0 to nblockV - NCOLORS do
      state[i, y + 1] := TList.Create;  //prepare next column

    for x := 0 to nblockV - NCOLORS - 1 do
    begin

      if stop then
        goto abort;
      Application.ProcessMessages;

      ndlist := state[x, y];
      for i := 0 to ndlist.Count - 1 do
      begin
        nd := TNode(ndlist.Items[i]);
        for ks := 0 to NVIALS - 1 do
        begin
          viS := nd.vial[ks].getTopInfo;
          if viS.empty = NVOLUME then
            continue;//source is empty vial
          for kd := 0 to NVIALS - 1 do
          begin
            if kd = ks then
              continue;//source vial= destination vial
            viD := nd.vial[kd].getTopInfo;

            if (viD.empty = 0)(*destination vial full*) or
              ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
              (*destination not empty and top colors different*) or
              ((viD.empty = NVOLUME) and (viS.topvol + viS.empty = NVOLUME))
            (*destinaion empty and only one color in source*) then
              continue;

            if (viD.empty < NVOLUME) and (viD.empty >= viS.topvol) then
              blockdecreaseQ := True //two color blocks are merged
            else
              blockdecreaseQ := False;

            vmin := Min(viD.empty, viS.topvol);
            ndnew := TNode.Create(nd);
            for j := 1 to vmin do
            begin
              ndnew.vial[kd].color[viD.empty - j] := TCls(viS.topcol);
              ndnew.vial[ks].color[viS.empty - 1 + j] := EMPTY;
            end;
            sortNode(ndnew, 0, NVIALS - 1);
            ndnew.hash := ndnew.getHash;
            if ndnew.isHashedQ then
            begin
              ndnew.Free;
              continue; //node presumely already exists, no hash collision detection
            end;
            ndnew.writeHashbit;
            Inc(total);
            if total > N_MAXNODES then
            begin
              Form1.Memo1.Lines.Add('');
              Form1.Memo1.Lines.Add(Format('Node limit %d exceeded!', [N_MAXNODES]));
              stop := True;
              goto abort;
            end;
            ndnew.mvInfo.srcVial := nd.vial[ks].pos;
            ndnew.mvInfo.dstVial := nd.vial[kd].pos;
            if blockdecreaseQ then
            begin
              ndnew.mvInfo.merged := True;
              state[x + 1, y].Add(ndnew);
            end
            else
            begin
              ndnew.mvInfo.merged := False;
              state[x, y + 1].Add(ndnew);
              Inc(newnodes);//new node in next column
            end;

          end;//destination vial;
        end;//source vial
      end;//list interation

    end; //column interation
    if state[nblockV - NCOLORS, y].Count > 0 then
      solutionFound := True;
    Inc(y); //next column
  until solutionFound or (newnodes = 0);

  Form1.Memo1.Lines.Add('');
  Form1.Memo1.Lines.Add(Format('%d nodes generated', [total]));
  Form1.Memo1.Lines.Add(optimalSolution_multi(nblockV, y - 1));
  Exit;

  abort:
    Form1.Memo1.Lines.Add(optimalSolution_multi(nblockV, y));

end;



{ TNode }
constructor TNode.Create(t: TVialsDef);
var
  i, nvial: integer;
begin
  nvial := High(t);
  Setlength(self.vial, nvial + 1);
  for i := 0 to nvial do
    self.vial[i] := TVial.Create(t[i], i);
  self.hash := getHash;
end;

constructor TNode.Create(node: TNode);
var
  i, nvial: integer;
begin
  nvial := High(node.vial);
  Setlength(self.vial, nvial + 1);
  for i := 0 to nvial do
  begin
    self.vial[i] := TVial.Create(node.vial[i].color, node.vial[i].pos);
  end;
  self.hash := node.hash;
end;

destructor TNode.Destroy;
var
  n, i: integer;
begin
  n := High(self.vial);
  for i := 0 to n do
    self.vial[i].Destroy;
  Setlength(self.vial, 0);

  inherited;
end;

procedure TNode.printRaw(w: TMemo);
var
  s, sn: string;
  hv, hc, i, j: integer;
begin
  hv := High(self.vial);
  hc := High(self.vial[1].color);
  for i := 0 to hc do
  begin
    s := '';
    for j := 0 to hv do
    begin
      sn := IntToStr(byte(self.vial[j].color[i]));
      s := s + Format('%5s', [sn]);
    end;
    w.Lines.Add(s);
  end;
  w.Lines.Add('');
end;

procedure TNode.print(w: TMemo);
var
  s, sn: string;
  hv, hc, i, j: integer;
  vialpos: array of byte;
begin
  hv := High(self.vial);
  hc := High(self.vial[1].color);
  SetLength({%H-}vialpos, hv + 1); //{%H-} to supress warning
  for i := 0 to hv do
    vialpos[self.vial[i].pos] := i;
  for i := 0 to hc do
  begin
    s := '';
    for j := 0 to hv do
    begin
      sn := IntToStr(byte(self.vial[vialpos[j]].color[i]));
      s := s + Format('%5s', [sn]);
    end;
    w.Lines.Add(s);
  end;
  w.Lines.Add('');
end;

function TNode.getHash: UInt32;
var
  p, v: integer;
begin
  Result := 0;
  for v := 0 to NVIALS - 1 do
    for p := 0 to NVOLUME - 1 do
    begin
      Result := Result xor hsh[integer(self.vial[v].color[p]), p, v];
    end;
end;

procedure TNode.writeHashbit;
var
  base, offset: integer;
begin
  base := self.hash div 64;
  offset := self.hash mod 64;
  hashbits[base] := hashbits[base] or (UInt64(1) shl offset);
end;

function TNode.isHashedQ: boolean;
var
  base, offset: integer;
begin
  base := self.hash div 64;
  offset := self.hash mod 64;
  if (hashbits[base] and (UInt64(1) shl offset)) <> 0 then
    Result := True
  else
    Result := False;
end;

function TNode.nodeBlocks: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to NVIALS - 1 do
  begin
    Inc(Result, self.vial[i].vialBlocks);
    //we count emtpty vials as 1 block in singleBLock mode
    //if singleMode and (self.vial[i].color[NVOLUME - 1] = EMPTY) then
    //  Inc(Result);
  end;

end;

function TNode.equalQ(node: TNode): boolean;
  //test vials for equality. vials are assumed to be already sorted.
var
  i, j: integer;
begin
  Result := True;
  for i := 0 to NVIALS - 1 do
    for j := 0 to NVOLUME - 1 do
    begin
      if self.vial[i].color[j] <> node.vial[i].color[j] then
        exit(False);
    end;
end;




function TNode.lastmoves: string;
  //we assume nd is sorted
var
  i, j, k, n, cl, src, dst, vol: integer;
  ft: string;
begin
  if NVIALS > 9 then
    ft := '%2d->%2d  '
  else
    ft := '%d->%d  ';
  Result := '';


  for i := 1 to NCOLORS do
  begin
    j := NVIALS - 1;
    while self.vial[j].getTopInfo.topcol <> i do
      Dec(j);
    if self.vial[j].getTopInfo.empty = 0 then
      continue;//vial with this color is full
    for k := 0 to j - 1 do
      if self.vial[k].getTopInfo.topcol = i then
        for n := 0 to self.vial[k].getTopInfo.topvol - 1 do
          Result := Result + Format(ft, [self.vial[k].pos + 1, self.vial[j].pos + 1]);

  end;

  if Result = '' then
    Result := 'Puzzle is solved!';

end;


function TNode.Nlastmoves: integer;
var
  i: integer;
begin
  if singlemode then
  begin
    Result := 0;
    for i := 0 to NEMPTYVIALS - 1 do
      Inc(Result, self.vial[i].getTopInfo.topvol);

  end
  else
  begin
    Result := NEMPTYVIALS;
    for i := 0 to NEMPTYVIALS - 1 do
      if vial[i].color[NVOLUME - 1] = EMPTY then
        Dec(Result);
  end;
end;

function TNode.emptyVials: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to NVIALS - 1 do
    if self.vial[i].color[NVOLUME - 1] = EMPTY then
      Inc(Result);
end;

{ TVial }

constructor TVial.Create(var c: array of TCls; p: UInt8);
var
  i: integer;
begin
  Setlength(self.color, NVOLUME);
  for i := 0 to NVOLUME - 1 do
    self.color[i] := c[i];
  self.pos := p;
end;

destructor TVial.Destroy;
begin
  Setlength(self.color, 0);
  inherited;
end;

function TVial.getTopInfo: TVialTopInfo;
var
  i, cl: integer;
begin
  Result.topcol := 0;
  Result.empty := NVOLUME;
  Result.topvol := 0;
  if self.color[NVOLUME - 1] = EMPTY then
    Exit(Result);   //empty vial

  for i := 0 to NVOLUME - 1 do
    if self.color[i] <> EMPTY then
    begin
      cl := integer(self.color[i]);
      Result.topcol := cl;
      Result.empty := i;
      Break;
    end;
  Result.topvol := 1;
  for i := Result.empty + 1 to NVOLUME - 1 do
    if cl = integer(self.color[i]) then
      Inc(Result.topvol)
    else
      Break;
end;

function TVial.vialBlocks: integer;
var
  i: integer;
begin
  Result := 1;
  for i := 0 to NVOLUME - 2 do
    if self.color[i + 1] <> self.color[i] then
      Inc(Result);
  if self.color[0] = EMPTY then
    Dec(Result);
end;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);

begin
  init;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (ssShift in Shift) or (ssCtrl in Shift) then
    shifted := True
  else
    shifted := False;
  Panel1.Invalidate;
end;



procedure TForm1.FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  begin
    if (ssShift in Shift) or (ssCtrl in Shift) then
      shifted := True
    else
      shifted := False;
    Panel1.Invalidate;
  end;
end;



procedure TForm1.BSolveClick(Sender: TObject);
var
  s: string;
begin
  if singlemode then
    s := 'Solve near-optimal'
  else
    s := 'Solve optimal';
  if BSolve.Caption = s then
  begin
    stop := False;
    BSolve.Caption := 'Abort';
  end
  else
  begin
    stop := True;
    Exit;
  end;

  NColorsSpin.Enabled := False;
  NFreeVialSpin.Enabled := False;
  NVolumeSpin.Enabled := False;

  NCOLORS := NColorsSpin.Value;
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVOLUME := NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;

  init(False);


  Panel1.Invalidate;

  if CBSingle.Checked then
    solve_single(globVialdef)
  else
    solve_multi(globVialdef);

  BSolve.Caption := s;
  NColorsSpin.Enabled := True;
  NFreeVialSpin.Enabled := True;
  NVolumeSpin.Enabled := True;
end;

procedure TForm1.BUndoClick(Sender: TObject);
var
  i, j: integer;
begin
  if undoHist < 0 then
    Exit;
  for i := 0 to NVIALS - 1 do
    for j := 0 to NVOLUME - 1 do
      globVialdef[i, j] := vialsDefHist[undoHist][i, j];
  SetLength(vialsDefHist[undoHist], 0, 0);
  Dec(undoHist);
  Form1.Caption := APPNAME + ' - ' + IntToStr(undoHist + 1) + ' move(s)';
  Panel1.Invalidate;
end;

procedure TForm1.CBSingleChange(Sender: TObject);
begin
  if CBSingle.Checked then
  begin
    singleMode := True;
    BSolve.Caption := 'Solve near-optimal';
  end
  else
  begin
    singleMode := False;
    BSolve.Caption := 'Solve optimal';
  end;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  i: integer;
begin
  for i := 0 to undoHist do
    SetLength(vialsDefHist[i], 0, 0);
end;

procedure TForm1.NColorsSpinChange(Sender: TObject);
begin
  NCOLORS := NColorsSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;
  init;
end;

procedure TForm1.NFreeVialSpinChange(Sender: TObject);
begin
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;
  init;
end;

procedure TForm1.NVolumeSpinChange(Sender: TObject);
begin
  NVOLUME := NVolumeSpin.Value;
  init;
end;



procedure TForm1.Panel1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  i, i1, j, ks, kd, tmp: integer;
  p: TPanel;
  xhVial, yhBlock, dx, dy: double;
  scol: TCls;
label
  edit, noswap;
begin
  p := Sender as TPanel;
  xhVial := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  if shifted then
    goto edit;//edit modus
  for i := 0 to NVIALS - 1 do
  begin
    dx := XOFF + i * (xhVial + XOFF);
    if (Round(dx) <= X) and (X < Round(dx + xhVial)) then
    begin
      if srcVial > -1 then
      begin
        if srcVial = i then
        begin
          srcVial := -1;
          dstVial := -1;
        end
        else
        begin

          dstVial := i;

          //try to pour src into dst
          if globVialdef[srcVial, NVOLUME - 1] = EMPTY then
          begin
            srcVial := -1;
            dstVial := -1;
            p.Invalidate;
            Exit;//empty source
          end
          else
          begin
            for j := 0 to NVOLUME - 1 do
            begin
              if globVialdef[srcVial, j] = EMPTY then
                continue
              else
              begin
                ks := j;
                break;
              end;
            end;
            if globVialdef[dstVial, NVOLUME - 1] = EMPTY then
              kd := NVOLUME
            else
            begin
              for j := 0 to NVOLUME - 1 do
              begin
                if globVialdef[dstVial, j] = EMPTY then
                  continue
                else
                begin
                  kd := j;
                  break;
                end;
              end;
            end;



            if (kd < NVOLUME) and (globVialdef[srcVial, ks] <>
              globVialdef[dstVial, kd]) or (kd = 0) then  //kd=0 is full vial
            begin
              srcVial := -1;
              dstVial := -1;
              p.Invalidate;
              Exit;
            end
            else
            begin
              Inc(undoHist); //save old position in history
              SetLength(vialsDefHist[undoHist], NVIALS, NVOLUME);
              for i1 := 0 to NVIALS - 1 do
                for j := 0 to NVOLUME - 1 do
                  vialsDefHist[undoHist][i1, j] := globVialdef[i1, j];

              if not singleMode then
              begin
                scol := globVialdef[srcVial, ks];
                repeat
                  globVialdef[dstVial, kd - 1] := globVialdef[srcVial, ks];
                  globVialdef[srcVial, ks] := EMPTY;
                  Inc(ks);
                  Dec(kd);
                until (ks = NVOLUME) or (kd = 0) or (globVialdef[srcVial, ks] <> scol);

              end
              else
              begin
                globVialdef[dstVial, kd - 1] := globVialdef[srcVial, ks];
                globVialdef[srcVial, ks] := EMPTY;
              end;


              srcVial := -1;
              dstVial := -1;
              Form1.Caption :=
                APPNAME + ' - ' + IntToStr(undoHist + 1) + ' move(s)';
              p.Invalidate;
            end;
          end;
        end;

      end
      else
        srcVial := i;
      p.Invalidate;
      break;
    end;
  end;
  Exit;
  edit: //exchange two blocks
    // xhBlock := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
    yhBlock := (p.Height - 2 * YOFF) / NVOLUME;

  for i := 0 to NVIALS - 1 do
  begin
    dx := XOFF + i * (xhVial + XOFF);
    if (Round(dx) <= X) and (X < Round(dx + xhVial)) then  //Vial i
      for j := 0 to NVOLUME - 1 do
      begin
        dy := YOFF + j * yhBlock;
        if (Round(dy) <= Y) and (Y < Round(dy + yhBlock)) then //Block j
          //Memo1.Lines.Add(Format('%d %d',[i,j]));
          if srcblock > -1 then
          begin
            if (srcvial = i) and (srcblock = j) then
            begin
              srcvial := -1;
              srcblock := -1;
              dstvial := -1;
              dstblock := -1;
            end
            else
            begin
              dstblock := j;
              dstvial := i;
              //some color swaps which use empty blocks are forbidden
              if (globVialdef[dstvial, dstblock] = EMPTY) then
              begin
                tmp := srcblock;
                srcblock := dstblock;
                dstblock := tmp;
                tmp := srcvial;
                srcvial := dstvial;
                dstvial := tmp;
              end;
              if (globVialdef[srcvial, srcblock] = EMPTY) then
              begin
                if (srcblock < NVOLUME - 1) and
                  (globVialdef[srcvial, srcblock + 1] = EMPTY) or
                  (dstblock > 0) and (globVialdef[dstvial, dstblock - 1] <>
                  EMPTY) or ((srcvial = dstvial) and (dstblock = srcblock + 1))
                then
                  goto noswap;
              end;
              scol := globVialdef[srcvial, srcblock];
              globVialdef[srcvial, srcblock] := globVialdef[dstvial, dstblock];
              globVialdef[dstvial, dstblock] := scol;
              Panel1.Invalidate;
              noswap:
                srcvial := -1;
              srcblock := -1;
              dstvial := -1;
              dstblock := -1;
              Exit;
            end;

          end
          else
          begin
            srcblock := j;
            srcvial := i;
            Exit;
          end;

      end; //j

  end;
end;

procedure plotVial(p: TPanel; idx: integer);
//idx is zero based
var
  cv: TCanvas;
  xhVial, yVial, dx: double;
begin

  xhVial := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  yVial := p.Height - 2 * YOFF;
  dx := XOFF + idx * (xhVial + XOFF);
  cv := p.Canvas;
  if (srcVial = idx) and not shifted then
  begin
    cv.Pen.Color := clBlack;
    cv.Pen.Width := 12;
  end
  //else if dstVial = idx then
  //begin
  //cv.Pen.Color := clRed;
  //cv.Pen.Width := 8;
  //end
  else
  begin
    cv.Pen.Color := clBlack;
    cv.Pen.Width := 2;
  end;

  cv.Line(Round(dx), YOFF, Round(dx + xhVial), YOFF);
  cv.LineTo(Round(dx + xhVial), Round(YOFF + yVial));
  cv.LineTo(Round(dx), Round(YOFF + yVial));
  cv.LineTo(Round(dx), YOFF);
  cv.Brush.Style := bsClear;
  cv.Font.Size := 12;
  cv.Font.Color := clBlack;
  cv.TextOut(Round(dx + xhVial / 2.3), Round(YOFF + yVial), IntToStr(idx + 1));
end;

procedure plotBlock(p: TPanel; nv, np, cl: integer);
//nv: vial, np:position in vial, cl: color
var
  cv: TCanvas;
  xhBlock, yhBlock, dx, dy: double;
begin
  xhBlock := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  yhBlock := (p.Height - 2 * YOFF) / NVOLUME;
  dx := XOFF + nv * (xhBlock + XOFF);
  dy := YOFF + np * yhBlock;
  cv := p.Canvas;
  cv.Pen.Width := 2;
  cv.Brush.Color := cols[cl];
  if shifted then
    cv.Pen.Color := clBlack
  else
    cv.Pen.Color := cols[cl];
  cv.Rectangle(Round(dx), Round(dy), Round(dx + xhBlock), Round(dy + yHBlock));
end;



procedure TForm1.Panel1Paint(Sender: TObject);
var
  i, j: integer;
  cv: TCanvas;
begin
  cv := panel1.Canvas;
  for i := 0 to NVIALS - 1 do
  begin
    for j := 0 to NVOLUME - 1 do
      plotBlock(Panel1, i, j, integer(globVialdef[i, j]));
    plotVial(Panel1, i);
  end;
  if shifted then
  begin
    cv.Font.Size := 10;
    cv.Font.Color := clRed;
    if srcblock = -1 then
      cv.TextOut(0, 0, 'Select first block')
    else
      cv.TextOut(0, 0, 'Select second block');

  end;
end;

procedure TForm1.TBRandomClick(Sender: TObject);
var
  tmp: TCls;
  i, j: integer;
begin
  NCOLORS := NColorsSpin.Value;
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVOLUME := NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;


  init;

  Randomize;
  //Fisher-Jates-Shuffle
  for i := NVOLUME * NCOLORS - 1 downto 1 do
  begin
    j := Random(i + 1);
    tmp := globVialdef[j div NVOLUME, j mod NVOLUME];
    globVialdef[j div NVOLUME, j mod NVOLUME] :=
      globVialdef[i div NVOLUME, i mod NVOLUME];
    globVialdef[i div NVOLUME, i mod NVOLUME] := tmp;
  end;

  Panel1.Invalidate;

  //nd := TNode.Create(globVialdef);
  //nd.print(Memo1);
  //solve(globVialdef);
  //Memo1.Lines.Add('done!');
  //nd.Free;
end;

end.

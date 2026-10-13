with Ada.Text_IO;                  use Ada.Text_IO;
with Ada.Characters.Handling;     use Ada.Characters.Handling;
with Ada.Numerics.Discrete_Random;

procedure Snake is

   -- Future me: these are the board dimensions, not the size of the terminal.
   -- If I change these, the snake can get longer/shorter without rewriting
   -- the movement rules. Keep the numbers reasonably small for now.
   Width     : constant := 20;
   Height    : constant := 12;
   Max_Cells : constant := Width * Height;

   subtype Grid_X is Integer range 1 .. Width;
   subtype Grid_Y is Integer range 1 .. Height;

   -- I'm keeping each square as an (X, Y) pair. It feels a little more
   -- readable than having separate arrays for every coordinate.
   type Position is record
      X : Integer;
      Y : Integer;
   end record;

   -- A snake cannot occupy more squares than the board has. This array
   -- stores the head first, then the body, then the tail.
   type Snake_Body is array (1 .. Max_Cells) of Position;

   -- Ada's random-number package needs a separate generator for each
   -- coordinate range. Slightly more setup than I expected, but straightforward.
   package Random_X is new Ada.Numerics.Discrete_Random (Grid_X);
   package Random_Y is new Ada.Numerics.Discrete_Random (Grid_Y);

   Gen_X : Random_X.Generator;
   Gen_Y : Random_Y.Generator;

   Snake_Parts : Snake_Body;
   Snake_Length : Natural range 1 .. Max_Cells := 3;

   Food : Position := (X => Width / 2, Y => Height / 2);

   -- These two numbers say which way the snake moves on the next turn.
   -- For example, (1, 0) means one square right; (0, -1) means up.
   DX : Integer := 1;
   DY : Integer := 0;

   Score       : Natural := 0;
   Game_Over   : Boolean := False;
   Won         : Boolean := False;

   -- Get one command per turn. This deliberately uses ordinary line input:
   -- type W/A/S/D and press Enter. It works in a plain terminal without
   -- needing special key-reading libraries or operating-system tricks.
   -- Future me: that means this version is turn-based, not smooth real-time.
   procedure Read_Move is
      Line  : String (1 .. 100);
      Last  : Natural;
      Key   : Character;
      New_DX : Integer := DX;
      New_DY : Integer := DY;
   begin
      Put ("Move (W/A/S/D), or Q to quit: ");
      Get_Line (Line, Last);

      if Last = 0 then
         return;
      end if;

      Key := To_Lower (Line (1));

      case Key is
         when 'w' =>
            New_DX := 0;
            New_DY := -1;
         when 's' =>
            New_DX := 0;
            New_DY := 1;
         when 'a' =>
            New_DX := -1;
            New_DY := 0;
         when 'd' =>
            New_DX := 1;
            New_DY := 0;
         when 'q' =>
            Game_Over := True;
            return;
         when others =>
            Put_Line ("I don't know that key. Try W, A, S, D, or Q.");
            return;
      end case;

      -- I don't want the snake to instantly turn back into itself.
      -- Without this check, a longer snake could hit its own neck by accident.
      if not (New_DX = -DX and New_DY = -DY) then
         DX := New_DX;
         DY := New_DY;
      end if;
   end Read_Move;


   procedure Place_Food is
      Candidate : Position;
      Occupied  : Boolean;
   begin
      -- Pick a square, then check whether the snake is already there.
      -- This loop is fine while the board has space. If every square is
      -- filled, the caller should end the game before asking for more food.
      loop
         Candidate.X := Random_X.Random (Gen_X);
         Candidate.Y := Random_Y.Random (Gen_Y);
         Occupied := False;

         for I in 1 .. Snake_Length loop
            if Snake_Parts (I).X = Candidate.X
              and then Snake_Parts (I).Y = Candidate.Y
            then
               Occupied := True;
               exit;
            end if;
         end loop;

         exit when not Occupied;
      end loop;

      Food := Candidate;
   end Place_Food;


   procedure Draw_Board is
   begin
      New_Line;
      Put_Line ("+" & (1 .. Width => '-') & "+");

      for Y in 1 .. Height loop
         Put ("|");

         for X in 1 .. Width loop
            if Snake_Parts (1).X = X and then Snake_Parts (1).Y = Y then
               Put ("@");  -- @ is the head, so I can spot it quickly.
            elsif Food.X = X and then Food.Y = Y then
               Put ("*");  -- The star is the food.
            else
               declare
                  Is_Body : Boolean := False;
               begin
                  -- Start at 2 because item 1 is the head, already handled.
                  for I in 2 .. Snake_Length loop
                     if Snake_Parts (I).X = X
                       and then Snake_Parts (I).Y = Y
                     then
                        Is_Body := True;
                        exit;
                     end if;
                  end loop;

                  if Is_Body then
                     Put ("o");
                  else
                     Put (" ");
                  end if;
               end;
            end if;
         end loop;

         Put_Line ("|");
      end loop;

      Put_Line ("+" & (1 .. Width => '-') & "+");
      Put_Line ("Score:" & Natural'Image (Score));
      Put_Line ("Legend: @ = head, o = body, * = food");
      New_Line;
   end Draw_Board;


   procedure Reset_Game is
   begin
      -- Reset all the things that belong to a new round. I nearly forgot
      -- direction the first time I made a game, and that gets confusing fast.
      Score := 0;
      Snake_Length := 3;
      DX := 1;
      DY := 0;
      Game_Over := False;
      Won := False;

      Snake_Parts (1) := (X => Width / 2,     Y => Height / 2);
      Snake_Parts (2) := (X => Width / 2 - 1, Y => Height / 2);
      Snake_Parts (3) := (X => Width / 2 - 2, Y => Height / 2);

      Place_Food;
   end Reset_Game;


   procedure Take_Turn is
      New_Head : Position;
      Ate_Food : Boolean;
      Hit_Self : Boolean := False;
   begin
      Read_Move;

      -- Q sets Game_Over in Read_Move. Don't sneak in one last move afterward.
      if Game_Over then
         return;
      end if;

      New_Head := (X => Snake_Parts (1).X + DX,
                   Y => Snake_Parts (1).Y + DY);

      -- First check the walls. The board doesn't wrap around in this version.
      if New_Head.X < 1 or else New_Head.X > Width
        or else New_Head.Y < 1 or else New_Head.Y > Height
      then
         Game_Over := True;
         return;
      end if;

      Ate_Food := New_Head.X = Food.X and then New_Head.Y = Food.Y;

      -- Check whether the new head lands on the snake itself.
      -- Important little detail: if we are NOT eating, the tail moves away
      -- this turn, so stepping onto the old tail square is actually okay.
      for I in 1 .. Snake_Length loop
         if (I < Snake_Length or else Ate_Food)
           and then Snake_Parts (I).X = New_Head.X
           and then Snake_Parts (I).Y = New_Head.Y
         then
            Hit_Self := True;
            exit;
         end if;
      end loop;

      if Hit_Self then
         Game_Over := True;
         return;
      end if;

      if Ate_Food then
         -- Add one body segment by making room at the end of the array.
         -- The board has a fixed maximum, so check that before growing.
         if Snake_Length = Max_Cells then
            Won := True;
            Game_Over := True;
            return;
         end if;

         Snake_Length := Snake_Length + 1;
         Score := Score + 10;
      end if;

      -- Move from the tail toward the head so we don't overwrite a segment
      -- before copying it. This order is easy to get wrong; keep it descending.
      for I in reverse 2 .. Snake_Length loop
         Snake_Parts (I) := Snake_Parts (I - 1);
      end loop;

      Snake_Parts (1) := New_Head;

      if Ate_Food then
         if Snake_Length = Max_Cells then
            Won := True;
            Game_Over := True;
         else
            Place_Food;
         end if;
      end if;
   end Take_Turn;


   Answer : Character;
begin
   Random_X.Reset (Gen_X);
   Random_Y.Reset (Gen_Y);

   Put_Line ("SNAKE - a small Ada learning project");
   Put_Line ("Controls: W = up, A = left, S = down, D = right.");
   Put_Line ("Type one letter and press Enter after each move.");
   Put_Line ("Eat * food, avoid the walls and your own body.");
   Put_Line ("Press Q during a turn to quit.");
   New_Line;

   loop
      Reset_Game;

      while not Game_Over loop
         Draw_Board;
         Take_Turn;
      end loop;

      Draw_Board;

      if Won then
         Put_Line ("You filled the whole board. You win!");
      elsif Score > 0 or else not Game_Over then
         Put_Line ("Game over!");
      else
         Put_Line ("Round ended.");
      end if;

      Put_Line ("Final score:" & Natural'Image (Score));
      Put ("Play again? (Y/N): ");

      declare
         Line : String (1 .. 100);
         Last : Natural;
      begin
         Get_Line (Line, Last);
         exit when Last = 0 or else To_Lower (Line (1)) /= 'y';
      end;
   end loop;

   Put_Line ("Thanks for playing. Future me: maybe add proper real-time keys later.");
end Snake;

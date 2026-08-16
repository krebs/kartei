# kartei's own library, so it doesn't depend on any external lib
# (e.g. stockholm).  Takes nixpkgs' lib and extends it with the few
# helpers needed by the host definitions.
{ lib ? import <nixpkgs/lib> }:
let
  kartei-lib = with kartei-lib; lib // builtins // {

    krebs.genipv6 = import ./genipv6.nix kartei-lib;

    hexchars = stringToCharacters "0123456789abcdef";

    genid = kartei-lib.genid_uint32; # TODO remove
    genid_uint31 = x: ((kartei-lib.genid_uint32 x) + 16777216) / 2;
    genid_uint32 = import ./genid.nix { lib = kartei-lib; };

    systemd.encodeName = replaceStrings ["/"] ["\\x2f"];

    hashToLength = n: s: substring 0 n (hashString "sha256" s);

    dropLast = n: xs: reverseList (drop n (reverseList xs));
    takeLast = n: xs: reverseList (take n (reverseList xs));

    test = re: x: isString x && testString re x;
    testString = re: x: match re x != null;

    # https://tools.ietf.org/html/rfc5952
    normalize-ip6-addr =
      let
        max-run-0 =
          let
            both = v: { off = v; pos = v; };
            gt = a: b: a.pos - a.off > b.pos - b.off;

            chkmax = ctx: {
              cur = both (ctx.cur.pos + 1);
              max = if gt ctx.cur ctx.max then ctx.cur else ctx.max;
            };

            incpos = ctx: recursiveUpdate ctx {
              cur.pos = ctx.cur.pos + 1;
            };

            f = ctx: blk: (if blk == "0" then incpos else chkmax) ctx;
            z = { cur = both 0; max = both 0; };
          in
            blks: (chkmax (foldl' f z blks)).max;

        group-zeros = a:
          let
            blks = splitString ":" a;
            max = max-run-0 blks;
            lhs = take max.off blks;
            rhs = drop max.pos blks;
          in
            if max.pos == 0
              then a
              else let
                sep =
                  if 8 - (length lhs + length rhs) == 1
                    then ":0:"
                    else "::";
              in
                "${concatStringsSep ":" lhs}${sep}${concatStringsSep ":" rhs}";

        drop-leading-zeros =
          let
            f = block:
              let
                res = match "0*(.+)" block;
              in
                if res == null
                  then block # empty block
                  else elemAt res 0;
          in
            a: concatStringsSep ":" (map f (splitString ":" a));
      in
        a:
          toLower
            (if test ".*::.*" a
              then a
              else group-zeros (drop-leading-zeros a));

    # Split string into list of chunks where each chunk is at most n chars long.
    # The leftmost chunk might shorter.
    # Example: stringToGroupsOf "123456" -> ["12" "3456"]
    stringToGroupsOf = n: s: let
      acc =
        foldl'
          (acc: c: if stringLength acc.chunk < n then {
            chunk = acc.chunk + c;
            chunks = acc.chunks;
          } else {
            chunk = c;
            chunks = acc.chunks ++ [acc.chunk];
          })
          {
            chunk = "";
            chunks = [];
          }
          (stringToCharacters s);
    in
      filter (x: x != []) ([acc.chunk] ++ acc.chunks);
  };
in
kartei-lib

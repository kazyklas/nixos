{ pkgs, ... }:

{
  programs.nixvim = {
    enable = true;
    colorschemes.tokyonight = {
      enable = true;
      settings = {
        style = "night";
        transparent = true;
      };
    };

    # force transparency everywhere
    extraConfigLua = ''
      vim.cmd("highlight Normal guibg=NONE ctermbg=NONE")
      vim.cmd("highlight NormalFloat guibg=NONE ctermbg=NONE")
      vim.cmd("highlight SignColumn guibg=NONE")
      vim.cmd("highlight LineNr guibg=NONE")
      vim.cmd("highlight EndOfBuffer guibg=NONE")
    '';

    viAlias = true;
    vimAlias = true;

    globals.mapleader = " ";

    opts = {
      termguicolors = true;
      scrolloff = 12;
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      smartindent = true;
      colorcolumn = "80";
    };

    highlight.ColorColumn = {
      bg = "#010101";
    };

    keymaps = [
      {
        mode = "n";
        key = "<leader>ff";
        action = "<cmd>Telescope find_files<CR>";
      }
      {
        mode = "n";
        key = "<leader>sg";
        action = "<cmd>Telescope live_grep<CR>";
      }
      {
        mode = "n";
        key = "<leader>e";
        action = "<cmd>NvimTreeToggle<CR>";
      }
      {
        mode = "n";
        key = "n";
        action = "nzzzv";
      }
      {
        mode = "n";
        key = "N";
        action = "Nzzzv";
      }
      {
        mode = "n";
        key = "<C-h>";
        action = "<C-w>h";
      }
      {
        mode = "n";
        key = "<C-l>";
        action = "<C-w>l";
      }
      {
        mode = "n";
        key = "<C-k>";
        action = "<C-w>k";
      }
      {
        mode = "n";
        key = "<C-j>";
        action = "<C-w>j";
      }
      {
        mode = "n";
        key = "<leader>t";
        action = "<cmd>set splitbelow | split | terminal<CR>";
      }
      {
        mode = "n";
        key = "<leader>gg";
        action = "<cmd>LazyGit<CR>";
      }
    ];

    plugins = {
      web-devicons.enable = true;

      lazygit.enable = true;

      lualine.enable = true;
      treesitter = {
        enable = true;
        settings.highlight.enable = true;
      };

      gitsigns.enable = true;
      comment.enable = true;
      nvim-autopairs.enable = true;
      telescope.enable = true;

      lsp = {
        enable = true;
        servers = {
          lua_ls = { enable = true; };
          pylsp = { enable = true; };
          ruff = { enable = true; };
          bashls = { enable = true; };
          nixd = { enable = true; };
          dockerls = { enable = true; };
          terraformls = { enable = true; };
        };
      };

      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            python = [ "ruff_format" ];
          };
          format_on_save = {
            timeout_ms = 500;
            lsp_fallback = true;
          };
        };
      };

      cmp = {
        enable = true;
        sources = [
          { name = "nvim_lsp"; }
          { name = "buffer"; }
          { name = "path"; }
        ];
      };

      nvim-tree = {
        enable = true;
      
        settings = {
          view = {
            width = 30;
            side = "left";
          };
      
          renderer = {
            group_empty = true;
          };
      
          filters = {
            dotfiles = false;
          };
        };
      };
    };
  };
}

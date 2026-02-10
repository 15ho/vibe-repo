SHELL := /bin/bash

# 源目录定义
CLAUDE_SKILLS_SRC := claude/skills
CURSOR_COMMANDS_SRC := cursor/commands

# 目标目录定义
CLAUDE_SKILLS_DEST := .claude/skills
CURSOR_COMMANDS_DEST := .cursor/commands

.PHONY: deploy help

help:
	@echo "AI 配置部署工具"
	@echo ""
	@echo "用法:"
	@echo "  make deploy TARGET=<目标项目路径>"
	@echo ""
	@echo "示例:"
	@echo "  make deploy TARGET=/path/to/project"
	@echo ""
	@echo "部署内容:"
	@echo "  - Claude Skills: oc-spec, oc-plan"
	@echo "  - Cursor Commands: gc.md"

deploy:
	@if [ -z "$(TARGET)" ]; then \
		echo "错误: 未指定 TARGET 参数"; \
		echo "用法: make deploy TARGET=<目标项目路径>"; \
		exit 1; \
	fi; \
	if [ ! -d "$(TARGET)" ]; then \
		echo "错误: 目标路径不存在或不是目录: $(TARGET)"; \
		exit 1; \
	fi; \
	echo "开始部署到: $(TARGET)"; \
	echo ""; \
	deployed=0; \
	skipped=0; \
	echo "=== 部署 Claude Skills ==="; \
	for skill_dir in $(CLAUDE_SKILLS_SRC)/*/; do \
		if [ -d "$$skill_dir" ]; then \
			skill_name=$$(basename "$$skill_dir"); \
			dest_dir="$(TARGET)/$(CLAUDE_SKILLS_DEST)/$$skill_name"; \
			if [ -d "$$dest_dir" ]; then \
				while true; do \
					printf "目录 $$dest_dir 已存在，是否覆盖？[y/n]: "; \
					read answer; \
					case "$$answer" in \
						[yY]) \
							rm -rf "$$dest_dir"; \
							mkdir -p "$$dest_dir"; \
							cp -r "$$skill_dir"* "$$dest_dir/"; \
							echo "已覆盖: $$dest_dir"; \
							deployed=$$((deployed + 1)); \
							break; \
							;; \
						[nN]) \
							echo "已跳过: $$dest_dir"; \
							skipped=$$((skipped + 1)); \
							break; \
							;; \
						*) \
							echo "请输入 y 或 n"; \
							;; \
					esac; \
				done; \
			else \
				mkdir -p "$$dest_dir"; \
				cp -r "$$skill_dir"* "$$dest_dir/"; \
				echo "已部署: $$dest_dir"; \
				deployed=$$((deployed + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "=== 部署 Cursor Commands ==="; \
	dest_cmd_dir="$(TARGET)/$(CURSOR_COMMANDS_DEST)"; \
	for cmd_file in $(CURSOR_COMMANDS_SRC)/*; do \
		if [ -f "$$cmd_file" ]; then \
			cmd_name=$$(basename "$$cmd_file"); \
			dest_file="$$dest_cmd_dir/$$cmd_name"; \
			if [ -f "$$dest_file" ]; then \
				while true; do \
					printf "文件 $$dest_file 已存在，是否覆盖？[y/n]: "; \
					read answer; \
					case "$$answer" in \
						[yY]) \
							mkdir -p "$$dest_cmd_dir"; \
							cp "$$cmd_file" "$$dest_file"; \
							echo "已覆盖: $$dest_file"; \
							deployed=$$((deployed + 1)); \
							break; \
							;; \
						[nN]) \
							echo "已跳过: $$dest_file"; \
							skipped=$$((skipped + 1)); \
							break; \
							;; \
						*) \
							echo "请输入 y 或 n"; \
							;; \
					esac; \
				done; \
			else \
				mkdir -p "$$dest_cmd_dir"; \
				cp "$$cmd_file" "$$dest_file"; \
				echo "已部署: $$dest_file"; \
				deployed=$$((deployed + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "========================================="; \
	echo "部署完成!"; \
	echo "  已部署: $$deployed 个文件"; \
	echo "  已跳过: $$skipped 个文件"; \
	echo "========================================="

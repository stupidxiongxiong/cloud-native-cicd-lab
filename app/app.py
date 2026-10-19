# ===================== 第1段：导入需要的工具 =====================
# os：Python 自带的模块，用来读取"系统环境变量"（后面数据库地址、密码都从环境变量读）
import os
# pymysql：第三方库，专门负责让 Python 和 MySQL 数据库"对话"（增删改查全靠它）
import pymysql
# Flask：Web 框架。它负责把"浏览器输入的网址"对应到"某段 Python 函数"，并把数据变成网页返回
#   request：用来接收网页表单提交的数据（比如用户在框里输入的待办内容）
#   redirect：处理完后跳转到另一个网址（比如添加完待办后跳回首页）
#   render_template_string：把数据填进一段 HTML 模板字符串里，生成最终网页
from flask import Flask, request, redirect, render_template_string

# 创建一个 Flask 应用实例，名字叫 app
# 后面所有 @app.route(...) 这种"网址→函数"的绑定，都挂在这个 app 上
app = Flask(__name__)

# ===================== 第2段：数据库连接信息（从环境变量读，不写死） =====================
# os.environ.get("环境变量名", "默认值") 的含义：
#   先去系统的环境变量里找这个名字；找不到，就用冒号后面的"默认值"
# 为什么从环境变量读、不直接写死？
#   → 代码里不写死 IP/密码，以后换数据库、上 K8s，只改环境变量、不用改代码（这叫"解耦"）
DB_HOST = os.environ.get("DB_HOST", "mysql")   # 数据库主机名，默认 "mysql"（块3 compose 里 mysql 服务的名字）
DB_USER = os.environ.get("DB_USER", "pb")      # 数据库用户名，默认 "pb"
DB_PASS = os.environ.get("DB_PASS", "<db_password>") # 数据库密码，部署时通过环境变量注入
DB_NAME = os.environ.get("DB_NAME", "pb")      # 数据库名，默认 "pb"

# ===================== 第3段：获取数据库连接的函数 =====================
# 每次要操作数据库，就调用 get_conn() 拿到一个"连接"对象
def get_conn():
    # pymysql.connect(...) 建立和 MySQL 的连接，返回连接对象
    return pymysql.connect(
        host=DB_HOST,        # 连哪台数据库（上面从环境变量读的）
        user=DB_USER,        # 登录用户名
        password=DB_PASS,    # 登录密码
        database=DB_NAME,    # 使用哪个数据库
        charset="utf8mb4",   # 字符集，支持中文和 emoji，避免乱码
        autocommit=True      # 自动提交：每条 SQL 执行后立刻生效，不用再手动 commit
    )

# ===================== 第4段：程序启动时自动建表 =====================
# tasks 这张表就是用来存待办事项的
def init_db():
    conn = get_conn()       # 开一个数据库连接
    # 执行建表 SQL。IF NOT EXISTS 表示：表已经存在就不建，不会报错（这叫"幂等"，重复跑安全）
    conn.cursor().execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INT AUTO_INCREMENT PRIMARY KEY,   # 自增主键，每条待办自动分配唯一 id
            title VARCHAR(255) NOT NULL,        # 待办内容，最长255字符，不能为空
            done TINYINT NOT NULL DEFAULT 0     # 完成状态：0=未完成，1=已完成，默认0
        )
    """)
    conn.close()            # 用完关闭连接，释放资源（好习惯）

init_db()  # 程序一启动就执行上面的建表函数，确保表一定存在

# ===================== 第5段：网页模板（一段 HTML 字符串） =====================
# 这是用户用浏览器看到的页面长什么样：上面一个"添加表单"，下面一个"待办列表"
# {{ }} 和 {% %} 是 Jinja2 模板语法（Flask 自带）：
#   {{ t[1] }} 表示把变量 t 的第2个元素（标题）显示出来
#   {% for t in tasks %} ... {% endfor %} 表示把 tasks 里的每一条循环显示出来
#   t[0]=id, t[1]=title, t[2]=done（和 SQL 查出来的列顺序对应）
PAGE = """
<!doctype html>
<html><body>
<h1>我的待办</h1>
<form method="post" action="/add">
  <input name="title" placeholder="写点什么..." required>
  <button>添加</button>
</form>
<ul>
{% for t in tasks %}
  <li>
    {% if t[2] %}<s>{{ t[1] }}</s>{% else %}{{ t[1] }}{% endif %}
    <a href="/toggle/{{ t[0] }}">[完成]</a>
    <a href="/delete/{{ t[0] }}">[删除]</a>
  </li>
{% endfor %}
</ul>
</body></html>
"""

# ===================== 第6段：四个路由 = 对应"增删改查" =====================
# 路由：@app.route("网址") 的意思是"用户访问这个网址时，就执行下面的函数"

# 【查】访问首页 "/"，列出所有待办
@app.route("/")
def index():
    conn = get_conn()                    # 开连接
    cur = conn.cursor()                  # 创建游标（真正执行 SQL 的工具）
    cur.execute("SELECT id, title, done FROM tasks ORDER BY id DESC")  # 查全部，按 id 倒序（新的在前）
    tasks = cur.fetchall()               # 取出所有结果（一个 list，每条是一行数据）
    conn.close()                         # 关连接
    # 把查到的 tasks 填进 PAGE 模板，生成网页返回给浏览器
    return render_template_string(PAGE, tasks=tasks)

# 【增】用户提交表单到 "/add"（POST 方式），往表里插入一条待办
@app.route("/add", methods=["POST"])
def add():
    title = request.form["title"]        # 从提交的表单里取用户填的 title
    conn = get_conn()
    cur = conn.cursor()
    # 这里的 %s 是占位符，title 作为第二个参数 (title,) 传进去，能防止 SQL 注入攻击
    cur.execute("INSERT INTO tasks (title) VALUES (%s)", (title,))
    conn.close()
    return redirect("/")                  # 添加完跳回首页

# 【改】访问 "/toggle/5" 把第5条标记为"完成/未完成"来回切换
@app.route("/toggle/<int:tid>")
def toggle(tid):
    conn = get_conn()
    cur = conn.cursor()
    # done=1-done：如果原来是0就变1，原来是1就变0（取反），实现"完成/取消完成"
    cur.execute("UPDATE tasks SET done=1-done WHERE id=%s", (tid,))
    conn.close()
    return redirect("/")

# 【删】访问 "/delete/5" 删除第5条
@app.route("/delete/<int:tid>")
def delete(tid):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM tasks WHERE id=%s", (tid,))
    conn.close()
    return redirect("/")

# ===================== 第7段：程序入口（标准写法） =====================
# 当你直接运行 `python3 app.py` 时，Python 会把 __name__ 设成 "__main__"，下面代码才会执行
# 如果这个文件是被别的文件 import 引入的，下面就不会执行（这是 Python 的惯例，照写即可）
if __name__ == "__main__":
    # 启动 Web 服务器
    # host="0.0.0.0" 表示接受来自任何地址的访问（必须这么写，容器外的浏览器才能访问进来）
    # port=5000 表示监听 5000 端口（浏览器访问 http://机器IP:5000）
    app.run(host="0.0.0.0", port=5000)

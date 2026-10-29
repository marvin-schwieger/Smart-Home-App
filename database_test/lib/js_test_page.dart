import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

class JsTestPage extends StatefulWidget {
  const JsTestPage({super.key});

  @override
  State<JsTestPage> createState() => _JsTestPageState();
}

class _JsTestPageState extends State<JsTestPage> {
  String _jsResult = '';
  late JavascriptRuntime flutterJs;
  @override
  void initState() {
    super.initState();

    flutterJs = getJavascriptRuntime();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlutterJS Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('JS Evaluate Result: $_jsResult\n'),
            SizedBox(height: 20,),
            Padding(padding: EdgeInsets.all(10), child: Text('Click on the big JS Yellow Button to evaluate the expression bellow using the flutter_js plugin'),),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("Math.trunc(Math.random() * 100).toString();", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        child: Image.asset('assets/js.ico'),
        onPressed: () async {
          try {
            JsEvalResult jsResult = flutterJs.evaluate(
                "Math.trunc(Math.random() * 100).toString();");
            setState(() {
              _jsResult = jsResult.stringResult;
            });
          } on PlatformException catch (e) {
            print('ERRO: ${e.details}');
          }
        },
      ),
    );
  }
}

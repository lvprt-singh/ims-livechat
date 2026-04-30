import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'quote_preview_screen.dart';

class QuoteLineItem {
  final TextEditingController product = TextEditingController();
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController price = TextEditingController();

  double get qtyValue => double.tryParse(qty.text) ?? 0;
  double get priceValue => double.tryParse(price.text) ?? 0;
  double get lineTotal => qtyValue * priceValue;

  void dispose() {
    product.dispose();
    qty.dispose();
    price.dispose();
  }

  Map<String, dynamic> toJson() => {
    'product': product.text.trim(),
    'qty': qtyValue,
    'price': priceValue,
    'total': lineTotal,
  };
}

class QuoteFormScreen extends StatefulWidget {
  final String chatId;
  final String customerName;
  final String customerEmail;
  final String chatEmailToken;

  const QuoteFormScreen({
    super.key,
    required this.chatId,
    required this.customerName,
    required this.customerEmail,
    required this.chatEmailToken,
  });

  @override
  State<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends State<QuoteFormScreen> {
  static const _red = Color(0xFFC81D24);
  static const _bg = Color(0xFFF7F7F8);

  late final TextEditingController _customerName;
  final _title = TextEditingController();
  final _rego = TextEditingController();
  final _carType = TextEditingController();
  final _transmission = TextEditingController();
  final _quoteBy = TextEditingController();

  final List<QuoteLineItem> _items = [QuoteLineItem()];

  @override
  void initState() {
    super.initState();
    _customerName = TextEditingController(text: widget.customerName);
    _customerName.addListener(_recalc);
    _quoteBy.addListener(_recalc);
    _title.addListener(_recalc);
    for (final item in _items) {
      item.product.addListener(_recalc);
      item.qty.addListener(_recalc);
      item.price.addListener(_recalc);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _customerName.dispose();
    _rego.dispose();
    _carType.dispose();
    _transmission.dispose();
    _quoteBy.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _recalc() => setState(() {});

  void _addLine() {
    final item = QuoteLineItem();
    item.product.addListener(_recalc);
    item.qty.addListener(_recalc);
    item.price.addListener(_recalc);
    setState(() => _items.add(item));
  }

  void _removeLine(int i) {
    if (_items.length <= 1) return;
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  double get _total => _items.fold(0, (s, i) => s + i.lineTotal);

  bool get _canPreview {
    if (_customerName.text.trim().isEmpty) return false;
    if (_title.text.trim().isEmpty) return false;
    if (_quoteBy.text.trim().isEmpty) return false;
    return _items.any(
      (i) => i.product.text.trim().isNotEmpty && i.priceValue > 0,
    );
  }

  void _openPreview() {
    final validItems = _items
        .where((i) => i.product.text.trim().isNotEmpty && i.priceValue > 0)
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuotePreviewScreen(
          chatId: widget.chatId,
          customerEmail: widget.customerEmail,
          chatEmailToken: widget.chatEmailToken,
          data: {
            'customer_name': _customerName.text.trim(),
            'title': _title.text.trim(),
            'rego': _rego.text.trim(),
            'car_type': _carType.text.trim(),
            'transmission': _transmission.text.trim(),
            'quote_by': _quoteBy.text.trim(),
            'items': validItems.map((i) => i.toJson()).toList(),
            'total': validItems.fold<double>(0, (s, i) => s + i.lineTotal),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        title: const Text(
          'New Quote',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section('Quote', [
                    _textField(_title, 'Quote title (e.g. Brake replacement)'),
                  ]),
                  const SizedBox(height: 16),
                  _section('Customer', [
                    _textField(_customerName, 'Customer name'),
                    _textField(
                      _rego,
                      'Rego',
                      textCapitalization: TextCapitalization.characters,
                    ),
                    _textField(_carType, 'Car make / model'),
                    _textField(_transmission, 'Transmission'),
                  ]),
                  const SizedBox(height: 16),
                  _section('Line items', [
                    for (int i = 0; i < _items.length; i++) _lineItemRow(i),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addLine,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          color: _red,
                        ),
                        label: const Text(
                          'Add another line',
                          style: TextStyle(
                            color: _red,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _section('Quote by', [_textField(_quoteBy, 'Mechanic name')]),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '\$${_total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _canPreview ? _openPreview : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Preview Quote',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: formatters,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400]),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _lineItemRow(int index) {
    final item = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          _textField(item.product, 'Product / service'),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _textField(
                  item.qty,
                  'Qty',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _textField(
                  item.price,
                  'Price (\$)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  formatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: _items.length > 1 ? _red : Colors.grey[300],
                ),
                onPressed: _items.length > 1 ? () => _removeLine(index) : null,
              ),
            ],
          ),
          if (item.lineTotal > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Line total: \$${item.lineTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
